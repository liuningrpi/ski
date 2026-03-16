import Foundation
import Combine
import CoreLocation
import UserNotifications
import FirebaseFirestore

// MARK: - Squad Models

enum SquadRole: String, Codable {
    case captain
    case member
}

enum SquadStatus: String, Codable {
    case active
    case ended
}

enum SquadAlertType: String, Codable {
    case selfCheck = "self_check"
    case stoppedWarning = "stopped_warning"
    case helpRequest = "help_request"
    case ping = "ping"
    case checkinOK = "checkin_ok"
}

struct SquadSessionInfo: Identifiable {
    let id: String
    let code: String
    let name: String
    let resort: String?
    let captainUID: String
    let shareOnlyWhenRecording: Bool
    let status: SquadStatus
    let createdAt: Date?
    let expiresAt: Date?
}

struct SquadMemberPresence: Identifiable {
    let id: String
    let uid: String
    let displayName: String
    let role: SquadRole
    let isSharing: Bool
    let isTracking: Bool
    let isPaused: Bool
    let lastUpdated: Date?
    let latitude: Double?
    let longitude: Double?
    let speed: Double?
    let altitude: Double?
    let accuracy: Double?
    let batteryLevel: Double?
    let pausedSharing: Bool
    let stoppedSince: Date?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isOnline: Bool {
        guard let lastUpdated else { return false }
        return Date().timeIntervalSince(lastUpdated) <= 60
    }

    var stoppedDuration: TimeInterval? {
        guard let stoppedSince else { return nil }
        return Date().timeIntervalSince(stoppedSince)
    }
}

struct SquadAlert: Identifiable {
    let id: String
    let type: SquadAlertType
    let sourceUID: String
    let sourceName: String
    let targetUID: String
    let message: String
    let createdAt: Date?
    let resolved: Bool
}

// MARK: - Squad Service

@MainActor
final class SquadService: ObservableObject {

    static let shared = SquadService()

    @Published var currentSession: SquadSessionInfo?
    @Published var members: [SquadMemberPresence] = []
    @Published var pendingSelfCheck: SquadAlert?
    @Published var isSharingPaused = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let db = Firestore.firestore()
    private let auth = AuthService.shared
    private var listeners: [ListenerRegistration] = []
    private var seenAlertIDs: Set<String> = []

    private var selfStopStart: Date?
    private var stationaryAnchor: CLLocation?
    private var lastSelfCheckAt: Date?
    private var lastSquadAlertAt: Date?
    private var selfCheckResponseDeadline: Date?
    private var pauseAlertsUntil: Date?

    private let selfCheckThreshold: TimeInterval = 180
    private let squadAlertThreshold: TimeInterval = 240
    private let selfCheckCooldown: TimeInterval = 600
    private let minStationaryAccuracy: Double = 25
    private let maxStationarySpeed: Double = 0.5
    private let maxStationaryDrift: Double = 15

    private let sessionDefaultsKey = "active_squad_session_id"
    private let firestoreTimeoutSeconds: Double = 12
    private var loadingRequestID: UUID?

    private init() {
        Task { [weak self] in
            await self?.requestNotificationPermissionIfNeeded()
        }
    }

    var isInSquad: Bool {
        currentSession != nil
    }

    var amCaptain: Bool {
        guard let uid = auth.currentUser?.uid else { return false }
        return currentSession?.captainUID == uid
    }

    func bootstrapIfNeeded() async {
        guard currentSession == nil,
              let uid = auth.currentUser?.uid,
              let savedSessionID = UserDefaults.standard.string(forKey: sessionDefaultsKey)
        else { return }

        do {
            let doc = try await db.collection("squadSessions").document(savedSessionID).getDocument()
            guard doc.exists, let data = doc.data(),
                  (data["status"] as? String ?? "active") == SquadStatus.active.rawValue else {
                clearSessionState(removeSavedID: true)
                return
            }

            let memberDoc = try await db.collection("squadSessions")
                .document(savedSessionID)
                .collection("members")
                .document(uid)
                .getDocument()

            guard memberDoc.exists else {
                clearSessionState(removeSavedID: true)
                return
            }

            if let info = parseSessionInfo(id: savedSessionID, data: data) {
                currentSession = info
                attachListeners(for: savedSessionID)
                statusMessage = "Rejoined squad \(info.code)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSquad(name: String, resort: String?, shareOnlyWhenRecording: Bool = true) async {
        guard let user = auth.currentUser else {
            errorMessage = "Please sign in first"
            return
        }

        let requestID = beginLoading(status: "Creating squad...")
        defer { endLoading(requestID: requestID) }

        do {
            let sessionRef = db.collection("squadSessions").document()
            let code = Self.generateInviteCode()
            let now = Date()
            let expiresAt = now.addingTimeInterval(24 * 60 * 60)
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = trimmedName.isEmpty ? "Ski Squad" : trimmedName

            try await withTimeout(seconds: self.firestoreTimeoutSeconds) {
                try await sessionRef.setData([
                    "code": code,
                    "name": finalName,
                    "resort": resort?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    "captainUID": user.uid,
                    "status": SquadStatus.active.rawValue,
                    "shareOnlyWhenRecording": shareOnlyWhenRecording,
                    "createdAt": FieldValue.serverTimestamp(),
                    "expiresAt": Timestamp(date: expiresAt)
                ])
            }

            try await withTimeout(seconds: self.firestoreTimeoutSeconds) {
                try await self.upsertMember(
                    sessionID: sessionRef.documentID,
                    uid: user.uid,
                    displayName: self.displayName(for: user),
                    role: .captain,
                    location: nil,
                    isTracking: false,
                    appPaused: false,
                    includeCoordinates: false
                )
            }

            let info = SquadSessionInfo(
                id: sessionRef.documentID,
                code: code,
                name: finalName,
                resort: resort,
                captainUID: user.uid,
                shareOnlyWhenRecording: shareOnlyWhenRecording,
                status: .active,
                createdAt: now,
                expiresAt: expiresAt
            )

            currentSession = info
            UserDefaults.standard.set(sessionRef.documentID, forKey: sessionDefaultsKey)
            attachListeners(for: sessionRef.documentID)
            statusMessage = "Squad created: \(code)"
        } catch {
            if error is TimeoutError {
                errorMessage = "Create squad timed out. Please check network and try again."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func joinSquad(code: String) async {
        guard let user = auth.currentUser else {
            errorMessage = "Please sign in first"
            return
        }

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            errorMessage = "Enter invitation code"
            return
        }

        let requestID = beginLoading(status: "Joining squad...")
        defer { endLoading(requestID: requestID) }

        do {
            let snapshot = try await withTimeout(seconds: self.firestoreTimeoutSeconds) {
                try await self.db.collection("squadSessions")
                    .whereField("code", isEqualTo: trimmed)
                    .whereField("status", isEqualTo: SquadStatus.active.rawValue)
                    .limit(to: 1)
                    .getDocuments()
            }

            guard let doc = snapshot.documents.first else {
                errorMessage = "Squad not found or expired"
                isLoading = false
                return
            }

            let data = doc.data()
            guard let info = parseSessionInfo(id: doc.documentID, data: data) else {
                errorMessage = "Invalid squad data"
                isLoading = false
                return
            }

            try await withTimeout(seconds: self.firestoreTimeoutSeconds) {
                try await self.upsertMember(
                    sessionID: doc.documentID,
                    uid: user.uid,
                    displayName: self.displayName(for: user),
                    role: .member,
                    location: nil,
                    isTracking: false,
                    appPaused: false,
                    includeCoordinates: false
                )
            }

            currentSession = info
            UserDefaults.standard.set(doc.documentID, forKey: sessionDefaultsKey)
            attachListeners(for: doc.documentID)
            statusMessage = "Joined squad \(info.code)"
        } catch {
            if error is TimeoutError {
                errorMessage = "Join squad timed out. Please check network and try again."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func leaveSquad() async {
        guard let sessionID = currentSession?.id,
              let uid = auth.currentUser?.uid
        else { return }

        do {
            try await db.collection("squadSessions")
                .document(sessionID)
                .collection("members")
                .document(uid)
                .delete()

            statusMessage = "You left the squad"
        } catch {
            errorMessage = error.localizedDescription
        }

        clearSessionState(removeSavedID: true)
    }

    func endSquadSession() async {
        guard amCaptain, let sessionID = currentSession?.id else { return }

        do {
            try await db.collection("squadSessions").document(sessionID).setData([
                "status": SquadStatus.ended.rawValue,
                "endedAt": FieldValue.serverTimestamp()
            ], merge: true)
            statusMessage = "Squad session ended"
        } catch {
            errorMessage = error.localizedDescription
        }

        clearSessionState(removeSavedID: true)
    }

    func setSharingPaused(_ paused: Bool) {
        isSharingPaused = paused
    }

    func respondSelfCheck(isOK: Bool) {
        Task {
            guard let session = currentSession,
                  let user = auth.currentUser,
                  let alert = pendingSelfCheck
            else { return }

            do {
                try await db.collection("squadSessions")
                    .document(session.id)
                    .collection("alerts")
                    .document(alert.id)
                    .setData([
                        "resolved": true,
                        "respondedAt": FieldValue.serverTimestamp(),
                        "response": isOK ? "ok" : "need_help"
                    ], merge: true)

                if isOK {
                    pauseAlertsUntil = Date().addingTimeInterval(selfCheckCooldown)
                    selfStopStart = nil
                    stationaryAnchor = nil
                    lastSquadAlertAt = nil
                    _ = await sendAlert(
                        sessionID: session.id,
                        type: .checkinOK,
                        sourceUID: user.uid,
                        sourceName: displayName(for: user),
                        targetUID: "all",
                        message: "\(displayName(for: user)) checked in: I'm OK"
                    )
                } else {
                    _ = await sendAlert(
                        sessionID: session.id,
                        type: .helpRequest,
                        sourceUID: user.uid,
                        sourceName: displayName(for: user),
                        targetUID: "all",
                        message: "\(displayName(for: user)) may need help. Check last shared location."
                    )
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                self.pendingSelfCheck = nil
                self.selfCheckResponseDeadline = nil
            }
        }
    }

    func pauseAlerts(minutes: Int) {
        pauseAlertsUntil = Date().addingTimeInterval(Double(minutes * 60))
        pendingSelfCheck = nil
        selfCheckResponseDeadline = nil
    }

    func sendPing(to member: SquadMemberPresence) {
        Task {
            guard let session = currentSession,
                  let user = auth.currentUser
            else { return }

            _ = await sendAlert(
                sessionID: session.id,
                type: .ping,
                sourceUID: user.uid,
                sourceName: displayName(for: user),
                targetUID: member.uid,
                message: "\(displayName(for: user)) pinged you"
            )
        }
    }

    func handleTrackerUpdate(location: CLLocation?, isTracking: Bool, isPaused appPaused: Bool) {
        guard let session = currentSession,
              let user = auth.currentUser
        else { return }

        let shouldShareLocation = !isSharingPaused
            && !appPaused
            && (!session.shareOnlyWhenRecording || isTracking)

        Task {
            do {
                try await upsertMember(
                    sessionID: session.id,
                    uid: user.uid,
                    displayName: displayName(for: user),
                    role: amCaptain ? .captain : .member,
                    location: location,
                    isTracking: isTracking,
                    appPaused: appPaused,
                    includeCoordinates: shouldShareLocation
                )
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                self.evaluateStoppedRisk(
                    location: location,
                    isTracking: isTracking,
                    appPaused: appPaused,
                    shouldShareLocation: shouldShareLocation,
                    sessionID: session.id,
                    user: user
                )
            }
        }
    }

    // MARK: - Internal

    private func evaluateStoppedRisk(
        location: CLLocation?,
        isTracking: Bool,
        appPaused: Bool,
        shouldShareLocation: Bool,
        sessionID: String,
        user: AppUser
    ) {
        let now = Date()

        if let until = pauseAlertsUntil, now < until {
            return
        }

        if !isTracking || appPaused || !shouldShareLocation || isSharingPaused {
            resetStoppedState()
            return
        }

        guard let location,
              location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= minStationaryAccuracy
        else {
            resetStoppedState()
            return
        }

        let speed = max(0, location.speed)

        if speed <= maxStationarySpeed {
            if let anchor = stationaryAnchor {
                let drift = location.distance(from: anchor)
                if drift > maxStationaryDrift {
                    stationaryAnchor = location
                    selfStopStart = now
                }
            } else {
                stationaryAnchor = location
                selfStopStart = now
            }
        } else {
            resetStoppedState()
            return
        }

        guard let stopStart = selfStopStart else { return }
        let stoppedDuration = now.timeIntervalSince(stopStart)

        if stoppedDuration >= selfCheckThreshold,
           pendingSelfCheck == nil,
           (lastSelfCheckAt == nil || now.timeIntervalSince(lastSelfCheckAt!) >= selfCheckCooldown) {
            lastSelfCheckAt = now
            selfCheckResponseDeadline = now.addingTimeInterval(60)

            Task {
                let alert = await sendAlert(
                    sessionID: sessionID,
                    type: .selfCheck,
                    sourceUID: user.uid,
                    sourceName: displayName(for: user),
                    targetUID: user.uid,
                    message: "You have been stationary for 3 minutes. Are you OK?"
                )
                await MainActor.run {
                    if let alert {
                        self.pendingSelfCheck = alert
                    }
                }
            }

            scheduleLocalNotification(
                title: "Safety check",
                body: "You have been stationary for 3 minutes. Tap Squad to confirm you're OK.",
                sound: .default
            )
        }

        if stoppedDuration >= squadAlertThreshold,
           let deadline = selfCheckResponseDeadline,
           now >= deadline,
           pendingSelfCheck != nil,
           (lastSquadAlertAt == nil || now.timeIntervalSince(lastSquadAlertAt!) > selfCheckCooldown) {
            lastSquadAlertAt = now

            Task {
                _ = await sendAlert(
                    sessionID: sessionID,
                    type: .stoppedWarning,
                    sourceUID: user.uid,
                    sourceName: displayName(for: user),
                    targetUID: "all",
                    message: "\(displayName(for: user)) has been stationary for over 4 minutes."
                )
            }
        }
    }

    private func resetStoppedState() {
        selfStopStart = nil
        stationaryAnchor = nil
        pendingSelfCheck = nil
        selfCheckResponseDeadline = nil
    }

    private func upsertMember(
        sessionID: String,
        uid: String,
        displayName: String,
        role: SquadRole,
        location: CLLocation?,
        isTracking: Bool,
        appPaused: Bool,
        includeCoordinates: Bool
    ) async throws {
        var data: [String: Any] = [
            "uid": uid,
            "displayName": displayName,
            "role": role.rawValue,
            "isSharing": includeCoordinates,
            "isTracking": isTracking,
            "isPaused": appPaused,
            "pausedSharing": isSharingPaused,
            "batteryLevel": UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : NSNull(),
            "lastUpdated": FieldValue.serverTimestamp()
        ]

        if let selfStopStart {
            data["stoppedSince"] = Timestamp(date: selfStopStart)
        } else {
            data["stoppedSince"] = FieldValue.delete()
        }

        if includeCoordinates, let location {
            data["lat"] = location.coordinate.latitude
            data["lng"] = location.coordinate.longitude
            data["speed"] = location.speed >= 0 ? location.speed : 0
            data["altitude"] = location.altitude
            data["accuracy"] = location.horizontalAccuracy
            data["ts"] = Timestamp(date: location.timestamp)
        } else {
            data["lat"] = FieldValue.delete()
            data["lng"] = FieldValue.delete()
            data["speed"] = FieldValue.delete()
            data["altitude"] = FieldValue.delete()
            data["accuracy"] = FieldValue.delete()
            data["ts"] = FieldValue.delete()
        }

        try await db.collection("squadSessions")
            .document(sessionID)
            .collection("members")
            .document(uid)
            .setData(data, merge: true)
    }

    private func sendAlert(
        sessionID: String,
        type: SquadAlertType,
        sourceUID: String,
        sourceName: String,
        targetUID: String,
        message: String
    ) async -> SquadAlert? {
        do {
            let ref = db.collection("squadSessions")
                .document(sessionID)
                .collection("alerts")
                .document()

            let now = Date()

            try await ref.setData([
                "type": type.rawValue,
                "sourceUID": sourceUID,
                "sourceName": sourceName,
                "targetUID": targetUID,
                "message": message,
                "resolved": false,
                "createdAt": FieldValue.serverTimestamp(),
                "clientCreatedAt": Timestamp(date: now)
            ])

            return SquadAlert(
                id: ref.documentID,
                type: type,
                sourceUID: sourceUID,
                sourceName: sourceName,
                targetUID: targetUID,
                message: message,
                createdAt: now,
                resolved: false
            )
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            return nil
        }
    }

    private func attachListeners(for sessionID: String) {
        clearListeners()

        let sessionListener = db.collection("squadSessions").document(sessionID)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self,
                      let data = snapshot?.data(),
                      let info = self.parseSessionInfo(id: sessionID, data: data)
                else { return }

                Task { @MainActor in
                    self.currentSession = info
                    if info.status != .active {
                        self.statusMessage = "Squad ended"
                        self.clearSessionState(removeSavedID: true)
                    }
                }
            }

        let membersListener = db.collection("squadSessions")
            .document(sessionID)
            .collection("members")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let documents = snapshot?.documents else { return }

                let parsed = documents.compactMap { doc in
                    self.parseMember(id: doc.documentID, data: doc.data())
                }
                .sorted { lhs, rhs in
                    if lhs.role != rhs.role {
                        return lhs.role == .captain
                    }
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }

                Task { @MainActor in
                    self.members = parsed
                }
            }

        let alertsListener = db.collection("squadSessions")
            .document(sessionID)
            .collection("alerts")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                Task { @MainActor in
                    self.handleIncomingAlerts(docs)
                }
            }

        listeners = [sessionListener, membersListener, alertsListener]
    }

    private func handleIncomingAlerts(_ docs: [QueryDocumentSnapshot]) {
        guard let me = auth.currentUser?.uid else { return }

        for doc in docs {
            guard !seenAlertIDs.contains(doc.documentID),
                  let alert = parseAlert(id: doc.documentID, data: doc.data())
            else { continue }

            seenAlertIDs.insert(doc.documentID)

            let isForMe = alert.targetUID == me || alert.targetUID == "all"
            guard isForMe else { continue }

            if alert.type == .selfCheck, alert.sourceUID == me, !alert.resolved {
                pendingSelfCheck = alert
                continue
            }

            if alert.sourceUID != me {
                scheduleLocalNotification(
                    title: "Squad Alert",
                    body: alert.message,
                    sound: .default
                )
            }
        }
    }

    private func parseSessionInfo(id: String, data: [String: Any]) -> SquadSessionInfo? {
        guard let code = data["code"] as? String,
              let captainUID = data["captainUID"] as? String
        else { return nil }

        let status = SquadStatus(rawValue: data["status"] as? String ?? "active") ?? .active
        let name = (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (name?.isEmpty == false ? name : nil) ?? "Ski Squad"
        let resort = (data["resort"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shareOnlyWhenRecording = data["shareOnlyWhenRecording"] as? Bool ?? true

        return SquadSessionInfo(
            id: id,
            code: code,
            name: finalName,
            resort: resort,
            captainUID: captainUID,
            shareOnlyWhenRecording: shareOnlyWhenRecording,
            status: status,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
        )
    }

    private func parseMember(id: String, data: [String: Any]) -> SquadMemberPresence? {
        guard let uid = data["uid"] as? String else { return nil }

        let role = SquadRole(rawValue: data["role"] as? String ?? "member") ?? .member
        let name = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (name?.isEmpty == false ? name : nil) ?? "User"

        return SquadMemberPresence(
            id: id,
            uid: uid,
            displayName: displayName,
            role: role,
            isSharing: data["isSharing"] as? Bool ?? false,
            isTracking: data["isTracking"] as? Bool ?? false,
            isPaused: data["isPaused"] as? Bool ?? false,
            lastUpdated: (data["lastUpdated"] as? Timestamp)?.dateValue(),
            latitude: data["lat"] as? Double,
            longitude: data["lng"] as? Double,
            speed: data["speed"] as? Double,
            altitude: data["altitude"] as? Double,
            accuracy: data["accuracy"] as? Double,
            batteryLevel: data["batteryLevel"] as? Double,
            pausedSharing: data["pausedSharing"] as? Bool ?? false,
            stoppedSince: (data["stoppedSince"] as? Timestamp)?.dateValue()
        )
    }

    private func parseAlert(id: String, data: [String: Any]) -> SquadAlert? {
        guard let typeRaw = data["type"] as? String,
              let type = SquadAlertType(rawValue: typeRaw),
              let sourceUID = data["sourceUID"] as? String,
              let sourceName = data["sourceName"] as? String,
              let targetUID = data["targetUID"] as? String,
              let message = data["message"] as? String
        else { return nil }

        return SquadAlert(
            id: id,
            type: type,
            sourceUID: sourceUID,
            sourceName: sourceName,
            targetUID: targetUID,
            message: message,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? (data["clientCreatedAt"] as? Timestamp)?.dateValue(),
            resolved: data["resolved"] as? Bool ?? false
        )
    }

    private func displayName(for user: AppUser) -> String {
        let trimmed = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        if let email = user.email, !email.isEmpty { return email }
        return "Skier"
    }

    private func clearListeners() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    private func clearSessionState(removeSavedID: Bool) {
        clearListeners()
        currentSession = nil
        members = []
        pendingSelfCheck = nil
        isSharingPaused = false
        resetStoppedState()
        seenAlertIDs.removeAll()
        if removeSavedID {
            UserDefaults.standard.removeObject(forKey: sessionDefaultsKey)
        }
    }

    private func scheduleLocalNotification(title: String, body: String, sound: UNNotificationSound?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        do {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func generateInviteCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    private struct TimeoutError: Error {}

    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func beginLoading(status: String) -> UUID {
        let requestID = UUID()
        loadingRequestID = requestID
        isLoading = true
        errorMessage = nil
        statusMessage = status

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            await MainActor.run {
                guard let self, self.loadingRequestID == requestID else { return }
                self.loadingRequestID = nil
                self.isLoading = false
                self.errorMessage = "Request timed out. Please check your network and try again."
                self.statusMessage = nil
            }
        }

        return requestID
    }

    private func endLoading(requestID: UUID) {
        guard loadingRequestID == requestID else { return }
        loadingRequestID = nil
        isLoading = false
    }
}
