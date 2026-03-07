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
                let mutualFriendUIDs = try await self.fetchMutualFriendUIDs(uid: user.uid)
                let allUIDs = [user.uid] + mutualFriendUIDs
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
            let fallbackName = user.displayName ?? user.email ?? "You"
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
            let fallbackName = user.displayName ?? user.email ?? "You"
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
        let defaultName = user?.displayName ?? user?.email ?? "You"
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

    private func fetchMutualFriendUIDs(uid: String) async throws -> [String] {
        let snapshot = try await friendsCollection(uid: uid).getDocuments()
        let directFriendUIDs = snapshot.documents.compactMap { doc -> String? in
            let accepted = doc.data()["accepted"] as? Bool ?? true
            return accepted ? doc.documentID : nil
        }

        guard !directFriendUIDs.isEmpty else { return [] }

        var mutuals: [String] = []
        for friendUID in directFriendUIDs {
            let reverse = try await friendsCollection(uid: friendUID).document(uid).getDocument()
            guard reverse.exists else { continue }
            let accepted = reverse.data()?["accepted"] as? Bool ?? true
            if accepted {
                mutuals.append(friendUID)
            }
        }
        return mutuals
    }

    private func fetchParticipants(
        uids: [String],
        fallbackCurrentUser: AppUser,
        fallbackCurrentStats: LeaderboardUserStats
    ) async throws -> [Participant] {
        var result: [Participant] = []

        for uid in uids {
            let doc = try await userDocument(uid: uid).getDocument()
            if let data = doc.data() {
                let name = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let email = data["email"] as? String
                let displayName = (name?.isEmpty == false ? name : nil) ?? email ?? "User"
                let stats = parseStats(from: data["leaderboardStats"] as? [String: Any])
                result.append(Participant(uid: uid, displayName: displayName, stats: stats))
            } else if uid == fallbackCurrentUser.uid {
                let fallbackName = fallbackCurrentUser.displayName ?? fallbackCurrentUser.email ?? "You"
                result.append(Participant(uid: uid, displayName: fallbackName, stats: fallbackCurrentStats))
            }
        }

        if result.isEmpty {
            let fallbackName = fallbackCurrentUser.displayName ?? fallbackCurrentUser.email ?? "You"
            result = [Participant(uid: fallbackCurrentUser.uid, displayName: fallbackName, stats: fallbackCurrentStats)]
        }

        return result
    }

    private func parseStats(from data: [String: Any]?) -> LeaderboardUserStats {
        guard let data else { return .zero }
        return LeaderboardUserStats(
            maxSpeedKmh: data["maxSpeedKmh"] as? Double ?? 0,
            bestRunDescentM: data["bestRunDescentM"] as? Double ?? 0,
            maxAltitudeM: data["maxAltitudeM"] as? Double ?? 0,
            longestRunDistanceKm: data["longestRunDistanceKm"] as? Double ?? 0,
            totalDistanceKm: data["totalDistanceKm"] as? Double ?? 0,
            runCount: data["runCount"] as? Int ?? 0,
            totalVerticalDropM: data["totalVerticalDropM"] as? Double ?? 0,
            totalDurationSec: data["totalDurationSec"] as? Double ?? 0
        )
    }

    // MARK: - Internal Participant

    private struct Participant {
        let uid: String
        let displayName: String
        let stats: LeaderboardUserStats
    }
}
