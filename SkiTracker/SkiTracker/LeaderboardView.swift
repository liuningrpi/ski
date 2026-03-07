import SwiftUI

// MARK: - Leaderboard View

struct LeaderboardView: View {

    @EnvironmentObject var sessionStore: SessionStore
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var authService = AuthService.shared
    @ObservedObject var leaderboardService = LeaderboardService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: LeaderboardCategory = .maxRecords
    @State private var selectedMetric: LeaderboardMetric = .maxSpeed

    private var availableMetrics: [LeaderboardMetric] {
        LeaderboardMetric.metrics(for: selectedCategory)
    }

    private var entries: [LeaderboardEntry] {
        leaderboardService.rankedEntries(metric: selectedMetric)
    }

    private var refreshToken: String {
        let uid = authService.currentUser?.uid ?? "guest"
        return "\(uid)-\(sessionStore.sessions.count)"
    }

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    categoryTabs
                    metricTabs
                    podiumBoard
                    rankingTable
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(.systemYellow).opacity(0.08),
                        Color(.systemBackground),
                        Color(.systemBlue).opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .navigationTitle(strings.leaderboard)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(strings.close) {
                        dismiss()
                    }
                }
            }
            .task(id: refreshToken) {
                await refreshLeaderboard()
            }
            .onChange(of: selectedCategory) { _, newValue in
                let metrics = LeaderboardMetric.metrics(for: newValue)
                if !metrics.contains(selectedMetric), let first = metrics.first {
                    selectedMetric = first
                }
            }
        }
    }

    // MARK: - Sections

    private var categoryTabs: some View {
        Picker("", selection: $selectedCategory) {
            Text(settings.strings.leaderboardCategoryMax).tag(LeaderboardCategory.maxRecords)
            Text(settings.strings.leaderboardCategoryMost).tag(LeaderboardCategory.mostRecords)
        }
        .pickerStyle(.segmented)
        .padding(.top, 8)
    }

    private var metricTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableMetrics) { metric in
                    Button {
                        selectedMetric = metric
                    } label: {
                        Text(metricTitle(metric))
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedMetric == metric ? Color.blue : Color(.systemGray6))
                            .foregroundColor(selectedMetric == metric ? .white : .primary)
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var podiumBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.strings.leaderboardOlympicBoard)
                .font(.headline)

            if leaderboardService.isLoading {
                HStack {
                    ProgressView()
                    Text(settings.strings.syncing)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if entries.isEmpty {
                Text(settings.strings.leaderboardNoData)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    podiumSlot(entry: entries.count > 1 ? entries[1] : nil, level: 2)
                    podiumSlot(entry: entries.first, level: 1)
                    podiumSlot(entry: entries.count > 2 ? entries[2] : nil, level: 3)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func podiumSlot(entry: LeaderboardEntry?, level: Int) -> some View {
        let boxHeight: CGFloat = {
            switch level {
            case 1: return 160
            case 2: return 130
            default: return 115
            }
        }()

        VStack(spacing: 8) {
            Text(rankMark(level))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(rankColor(level))

            if let entry {
                Text(entry.displayName)
                    .font(.subheadline)
                    .fontWeight(entry.uid == authService.currentUser?.uid ? .semibold : .regular)
                    .lineLimit(1)
                Text(scoreText(for: entry))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            } else {
                Text("-")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("--")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: boxHeight)
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(rankColor(level).opacity(0.10))
        .cornerRadius(14)
    }

    private var rankingTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(settings.strings.leaderboardFullRank)
                .font(.headline)

            if let error = leaderboardService.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        Text("#\(entry.rank)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .frame(width: 42)
                            .foregroundColor(rankColor(entry.rank))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.displayName)
                                .font(.subheadline)
                                .fontWeight(entry.uid == authService.currentUser?.uid ? .semibold : .regular)
                            if entry.uid == authService.currentUser?.uid {
                                Text(settings.strings.youLabel)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Text(scoreText(for: entry))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)

                    if entry.id != entries.last?.id {
                        Divider()
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )

            Text(leaderboardFooterText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func refreshLeaderboard() async {
        if let user = authService.currentUser {
            await leaderboardService.refreshLeaderboard(
                for: user,
                localSessions: sessionStore.sessions,
                showLoading: true
            )
        } else {
            leaderboardService.useLocalOnly(user: nil, sessions: sessionStore.sessions)
        }
    }

    private func metricTitle(_ metric: LeaderboardMetric) -> String {
        let strings = settings.strings
        switch metric {
        case .maxSpeed:
            return strings.leaderboardMetricTopSpeed
        case .maxRunDescent:
            return strings.leaderboardMetricTopRunDescent
        case .maxAltitude:
            return strings.leaderboardMetricMaxAltitude
        case .longestRunDistance:
            return strings.leaderboardMetricLongestRun
        case .totalDistance:
            return strings.leaderboardMetricTotalDistance
        case .totalRuns:
            return strings.leaderboardMetricRunCount
        case .totalVerticalDrop:
            return strings.leaderboardMetricTotalVerticalDrop
        case .totalDuration:
            return strings.leaderboardMetricTotalDuration
        }
    }

    private func scoreText(for entry: LeaderboardEntry) -> String {
        let units = settings.unitSystem
        let strings = settings.strings
        switch selectedMetric {
        case .maxSpeed:
            return "\(settings.formatSpeed(entry.stats.maxSpeedKmh)) \(units.speedUnit)"
        case .maxRunDescent:
            return "\(settings.formatAltitude(entry.stats.bestRunDescentM)) \(units.altitudeUnit)"
        case .maxAltitude:
            return "\(settings.formatAltitude(entry.stats.maxAltitudeM)) \(units.altitudeUnit)"
        case .longestRunDistance:
            return "\(settings.formatDistance(entry.stats.longestRunDistanceKm)) \(units.distanceUnit)"
        case .totalDistance:
            return "\(settings.formatDistance(entry.stats.totalDistanceKm)) \(units.distanceUnit)"
        case .totalRuns:
            return "\(entry.stats.runCount) \(strings.runsCount)"
        case .totalVerticalDrop:
            return "\(settings.formatAltitude(entry.stats.totalVerticalDropM)) \(units.altitudeUnit)"
        case .totalDuration:
            return formatDuration(seconds: entry.stats.totalDurationSec)
        }
    }

    private func formatDuration(seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%dh %02dm", h, m)
        }
        return String(format: "%02dm %02ds", m, s)
    }

    private func rankMark(_ rank: Int) -> String {
        switch rank {
        case 1: return "1"
        case 2: return "2"
        case 3: return "3"
        default: return "\(rank)"
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 0.80, green: 0.63, blue: 0.10)
        case 2: return Color(red: 0.55, green: 0.60, blue: 0.70)
        case 3: return Color(red: 0.65, green: 0.43, blue: 0.25)
        default: return .primary
        }
    }

    private var leaderboardFooterText: String {
        let strings = settings.strings
        if entries.count <= 1 {
            return strings.leaderboardSingleUserHint
        }
        return strings.leaderboardFriendsOnlyHint
    }
}

// MARK: - Preview

#Preview {
    LeaderboardView()
        .environmentObject(SessionStore())
}
