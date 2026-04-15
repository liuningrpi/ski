import Foundation
import Combine
import FirebaseFirestore

enum LeaderboardError: Error {
    case timeout
}

// MARK: - Leaderboard Category

enum LeaderboardCategory: String, CaseIterable, Identifiable {
    case maxRecords
    case mostRecords

    var id: String { rawValue }
}

// MARK: - Leaderboard Metric

enum LeaderboardMetric: String, CaseIterable, Identifiable {
    case maxSpeed
    case maxRunDescent
    case maxAltitude
    case longestRunDistance
    case totalDistance
    case totalRuns
    case totalVerticalDrop
    case totalDuration

    var id: String { rawValue }

    var category: LeaderboardCategory {
        switch self {
        case .maxSpeed, .maxRunDescent, .maxAltitude, .longestRunDistance:
            return .maxRecords
        case .totalDistance, .totalRuns, .totalVerticalDrop, .totalDuration:
            return .mostRecords
        }
    }

    static func metrics(for category: LeaderboardCategory) -> [LeaderboardMetric] {
        allCases.filter { $0.category == category }
    }
}

// MARK: - Leaderboard Stats

struct LeaderboardUserStats {
    let maxSpeedKmh: Double
    let bestRunDescentM: Double
    let maxAltitudeM: Double
    let longestRunDistanceKm: Double
    let totalDistanceKm: Double
    let runCount: Int
    let totalVerticalDropM: Double
    let totalDurationSec: Double

    static let zero = LeaderboardUserStats(
        maxSpeedKmh: 0,
        bestRunDescentM: 0,
        maxAltitudeM: 0,
        longestRunDistanceKm: 0,
        totalDistanceKm: 0,
        runCount: 0,
        totalVerticalDropM: 0,
        totalDurationSec: 0
    )

    func value(for metric: LeaderboardMetric) -> Double {
        switch metric {
        case .maxSpeed:
            return maxSpeedKmh
        case .maxRunDescent:
            return bestRunDescentM
        case .maxAltitude:
            return maxAltitudeM
        case .longestRunDistance:
            return longestRunDistanceKm
        case .totalDistance:
            return totalDistanceKm
        case .totalRuns:
            return Double(runCount)
        case .totalVerticalDrop:
            return totalVerticalDropM
        case .totalDuration:
            return totalDurationSec
        }
    }
}

// MARK: - Leaderboard Entry

struct LeaderboardEntry: Identifiable {
    let id: String
    let uid: String
    let displayName: String
    let rank: Int
    let stats: LeaderboardUserStats
}

// MARK: - Leaderboard Service

final class LeaderboardService: ObservableObject {

    static let shared = LeaderboardService()

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var participants: [Participant] = []
    private var loadingWatchdogTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    func refreshLeaderboard(
        for user: AppUser,
        localSessions: [TrackSession],
        showLoading: Bool = true
    ) async {
        startLoadingWatchdogIfNeeded(user: user, localSessions: localSessions, enabled: showLoading)
        defer {
            loadingWatchdogTask?.cancel()
            loadingWatchdogTask = nil
        }

        if showLoading {
            await MainActor.run {
                isLoading = true
                errorMessage = nil
            }
        } else {
            await MainActor.run {
                errorMessage = nil
            }
        }

        do {
            let localStats = computeStats(from: localSessions)
            let fetched = try await withTimeout(seconds: 12) { [self] in
                try await self.upsertStats(uid: user.uid, displayName: user.displayName, fallbackEmail: user.email, stats: localStats)
                let friendUIDs = try await self.fetchVisibleFriendUIDs(uid: user.uid)
                let allUIDs = [user.uid] + friendUIDs
                return try await self.fetchParticipants(uids: allUIDs, fallbackCurrentUser: user, fallbackCurrentStats: localStats)
            }

            await MainActor.run {
                participants = fetched
                if showLoading {
                    isLoading = false
                }
            }
        } catch {
            // Fallback to local self-only ranking to avoid blocking UI in syncing state.
            let localStats = computeStats(from: localSessions)
            let fallbackName = user.displayName ?? user.email ?? SettingsManager.shared.strings.youLabel
            let friendlyMessage: String
            if let e = error as? LeaderboardError, e == .timeout {
                friendlyMessage = SettingsManager.shared.strings.leaderboardSyncTimeout
            } else {
                friendlyMessage = error.localizedDescription
            }
            await MainActor.run {
                self.errorMessage = friendlyMessage
                self.participants = [
                    Participant(uid: user.uid, displayName: fallbackName, stats: localStats)
                ]
                if showLoading {
                    self.isLoading = false
                }
            }
        }
    }

    private func startLoadingWatchdogIfNeeded(user: AppUser, localSessions: [TrackSession], enabled: Bool) {
        loadingWatchdogTask?.cancel()
        guard enabled else { return }

        loadingWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard let self, !Task.isCancelled else { return }

            let fallbackStats = self.computeStats(from: localSessions)
            let fallbackName = user.displayName ?? user.email ?? SettingsManager.shared.strings.youLabel
            await MainActor.run {
                guard self.isLoading else { return }
                self.errorMessage = SettingsManager.shared.strings.leaderboardSyncTimeout
                self.participants = [
                    Participant(uid: user.uid, displayName: fallbackName, stats: fallbackStats)
                ]
                self.isLoading = false
            }
        }
    }

    func useLocalOnly(user: AppUser?, sessions: [TrackSession]) {
        let stats = computeStats(from: sessions)
        let uid = user?.uid ?? "local"
        let defaultName = user?.displayName ?? user?.email ?? SettingsManager.shared.strings.youLabel
        Task { @MainActor in
            self.errorMessage = nil
            self.isLoading = false
            self.participants = [
                Participant(uid: uid, displayName: defaultName, stats: stats)
            ]
        }
    }

    func rankedEntries(metric: LeaderboardMetric) -> [LeaderboardEntry] {
        let sorted = participants.sorted { lhs, rhs in
            let lv = lhs.stats.value(for: metric)
            let rv = rhs.stats.value(for: metric)
            if lv == rv {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lv > rv
        }

        return sorted.enumerated().map { index, participant in
            LeaderboardEntry(
                id: participant.uid,
                uid: participant.uid,
                displayName: participant.displayName,
                rank: index + 1,
                stats: participant.stats
            )
        }
    }

    // MARK: - Stats

    func computeStats(from sessions: [TrackSession]) -> LeaderboardUserStats {
        guard !sessions.isEmpty else { return .zero }

        let maxSpeed = sessions.map { $0.maxSpeedKmh }.max() ?? 0
        let maxAltitude = sessions.map { $0.maxAltitude }.max() ?? 0
        let totalDistance = sessions.reduce(0) { $0 + $1.totalDistanceKm }
        let totalDuration = sessions.reduce(0) { $0 + $1.durationSeconds }

        var runCount = 0
        var bestRunDescent = 0.0
        var longestRunDistance = 0.0
        var totalVerticalDrop = 0.0
        for session in sessions {
            let runs = session.skiingRuns
            runCount += runs.count
            totalVerticalDrop += session.totalVerticalDrop
            let localMax = runs.map { $0.elevationDrop }.max() ?? 0
            if localMax > bestRunDescent {
                bestRunDescent = localMax
            }
            let localLongestDistance = runs.map { $0.totalDistanceKm }.max() ?? 0
            if localLongestDistance > longestRunDistance {
                longestRunDistance = localLongestDistance
            }
        }

        return LeaderboardUserStats(
            maxSpeedKmh: maxSpeed,
            bestRunDescentM: bestRunDescent,
            maxAltitudeM: maxAltitude,
            longestRunDistanceKm: longestRunDistance,
            totalDistanceKm: totalDistance,
            runCount: runCount,
            totalVerticalDropM: totalVerticalDrop,
            totalDurationSec: totalDuration
        )
    }

    // MARK: - Firestore

    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw LeaderboardError.timeout
            }

            guard let first = try await group.next() else {
                throw LeaderboardError.timeout
            }
            group.cancelAll()
            return first
        }
    }

    private func userDocument(uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    private func friendsCollection(uid: String) -> CollectionReference {
        userDocument(uid: uid).collection("friends")
    }

    private func upsertStats(uid: String, displayName: String?, fallbackEmail: String?, stats: LeaderboardUserStats) async throws {
        let data: [String: Any] = [
            "displayName": displayName ?? "",
            "email": fallbackEmail ?? "",
            "leaderboardStats": [
                "maxSpeedKmh": stats.maxSpeedKmh,
                "bestRunDescentM": stats.bestRunDescentM,
                "maxAltitudeM": stats.maxAltitudeM,
                "longestRunDistanceKm": stats.longestRunDistanceKm,
                "totalDistanceKm": stats.totalDistanceKm,
                "runCount": stats.runCount,
                "totalVerticalDropM": stats.totalVerticalDropM,
                "totalDurationSec": stats.totalDurationSec
            ],
            "leaderboardUpdatedAt": FieldValue.serverTimestamp()
        ]

        try await userDocument(uid: uid).setData(data, merge: true)
    }

    private func fetchVisibleFriendUIDs(uid: String) async throws -> [String] {
        let snapshot = try await friendsCollection(uid: uid).getDocuments()
        return snapshot.documents.compactMap { doc -> String? in
            let accepted = doc.data()["accepted"] as? Bool ?? true
            let hiddenInCompetition = doc.data()["hiddenInCompetition"] as? Bool ?? false
            return (accepted && !hiddenInCompetition) ? doc.documentID : nil
        }
    }

    private func fetchParticipants(
        uids: [String],
        fallbackCurrentUser: AppUser,
        fallbackCurrentStats: LeaderboardUserStats
    ) async throws -> [Participant] {
        let youLabel = await MainActor.run { SettingsManager.shared.strings.youLabel }
        let db = self.db

        let fetched = try await withThrowingTaskGroup(of: Participant?.self) { group in
            for uid in uids {
                group.addTask {
                    let doc = try await db.collection("users").document(uid).getDocument()
                    if let data = doc.data() {
                        let name = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let email = data["email"] as? String
                        let displayName = (name?.isEmpty == false ? name : nil) ?? email ?? youLabel
                        let statsData = data["leaderboardStats"] as? [String: Any]
                        let stats = if let statsData, !statsData.isEmpty {
                            LeaderboardUserStats(
                                maxSpeedKmh: statsData["maxSpeedKmh"] as? Double ?? 0,
                                bestRunDescentM: statsData["bestRunDescentM"] as? Double ?? 0,
                                maxAltitudeM: statsData["maxAltitudeM"] as? Double ?? 0,
                                longestRunDistanceKm: statsData["longestRunDistanceKm"] as? Double ?? 0,
                                totalDistanceKm: statsData["totalDistanceKm"] as? Double ?? 0,
                                runCount: statsData["runCount"] as? Int ?? 0,
                                totalVerticalDropM: statsData["totalVerticalDropM"] as? Double ?? 0,
                                totalDurationSec: statsData["totalDurationSec"] as? Double ?? 0
                            )
                        } else {
                            try await self.fallbackStatsFromSessions(uid: uid)
                        }
                        return Participant(uid: uid, displayName: displayName, stats: stats)
                    }
                    if uid == fallbackCurrentUser.uid {
                        let fallbackName = fallbackCurrentUser.displayName ?? fallbackCurrentUser.email ?? youLabel
                        return Participant(uid: uid, displayName: fallbackName, stats: fallbackCurrentStats)
                    }
                    return nil
                }
            }

            var result: [Participant] = []
            for try await participant in group {
                if let participant {
                    result.append(participant)
                }
            }
            return result
        }

        if fetched.isEmpty {
            let fallbackName = fallbackCurrentUser.displayName ?? fallbackCurrentUser.email ?? youLabel
            return [Participant(uid: fallbackCurrentUser.uid, displayName: fallbackName, stats: fallbackCurrentStats)]
        }
        return fetched
    }

    // MARK: - Internal Participant

    private struct Participant {
        let uid: String
        let displayName: String
        let stats: LeaderboardUserStats
    }

    private func fallbackStatsFromSessions(uid: String) async throws -> LeaderboardUserStats {
        let snapshot = try await db.collection("users")
            .document(uid)
            .collection("sessions")
            .getDocuments()

        guard !snapshot.documents.isEmpty else {
            return .zero
        }

        var maxSpeedKmh = 0.0
        var maxAltitudeM = 0.0
        var totalDistanceKm = 0.0
        var totalDurationSec = 0.0
        var totalVerticalDropM = 0.0

        for doc in snapshot.documents {
            let data = doc.data()
            maxSpeedKmh = max(maxSpeedKmh, data["maxSpeedKmh"] as? Double ?? 0)
            maxAltitudeM = max(maxAltitudeM, data["maxAltitude"] as? Double ?? 0)
            totalDistanceKm += data["totalDistanceKm"] as? Double ?? 0
            totalDurationSec += data["durationSeconds"] as? Double ?? 0
            totalVerticalDropM += data["elevationDrop"] as? Double ?? 0
        }

        return LeaderboardUserStats(
            maxSpeedKmh: maxSpeedKmh,
            bestRunDescentM: 0,
            maxAltitudeM: maxAltitudeM,
            longestRunDistanceKm: 0,
            totalDistanceKm: totalDistanceKm,
            runCount: 0,
            totalVerticalDropM: totalVerticalDropM,
            totalDurationSec: totalDurationSec
        )
    }
}
