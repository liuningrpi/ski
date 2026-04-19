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
            SkiScreenBackground {
                ScrollView {
                    VStack(spacing: 16) {
                        categoryTabs
                        metricTabs
                        podiumBoard
                        rankingTable
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(strings.leaderboard)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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
        .tint(SkiPalette.primary)
    }

    private var metricTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableMetrics) { metric in
                    Button {
                        selectedMetric = metric
                    } label: {
                        Text(metricTitle(metric))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedMetric == metric ? SkiPalette.primary.opacity(0.95) : Color.black.opacity(0.24),
                                in: Capsule()
                            )
                            .foregroundStyle(selectedMetric == metric ? .white : SkiPalette.textSecondary)
                            .overlay(
                                Capsule()
                                    .stroke(selectedMetric == metric ? SkiPalette.primary.opacity(0.6) : SkiPalette.stroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var podiumBoard: some View {
        SkiGlassCard(cornerRadius: 28, padding: 16) {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.strings.leaderboardOlympicBoard)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(SkiPalette.textPrimary)

            if leaderboardService.isLoading {
                HStack {
                    ProgressView()
                        .tint(SkiPalette.textPrimary)
                    Text(settings.strings.syncing)
                        .foregroundStyle(SkiPalette.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if entries.isEmpty {
                Text(settings.strings.leaderboardNoData)
                    .foregroundStyle(SkiPalette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 10) {
                        podiumSlot(entry: entries.count > 1 ? entries[1] : nil, level: 2)
                        podiumSlot(entry: entries.first, level: 1)
                        podiumSlot(entry: entries.count > 2 ? entries[2] : nil, level: 3)
                    }
                    VStack(spacing: 10) {
                        podiumSlot(entry: entries.first, level: 1)
                        podiumSlot(entry: entries.count > 1 ? entries[1] : nil, level: 2)
                        podiumSlot(entry: entries.count > 2 ? entries[2] : nil, level: 3)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        }
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
                    .font(.system(size: 14, weight: entry.uid == authService.currentUser?.uid ? .bold : .semibold, design: .rounded))
                    .fontWeight(entry.uid == authService.currentUser?.uid ? .semibold : .regular)
                    .foregroundStyle(SkiPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(scoreText(for: entry))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(SkiPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                Text("-")
                    .font(.subheadline)
                    .foregroundStyle(SkiPalette.textSecondary)
                Text("--")
                    .font(.caption)
                    .foregroundStyle(SkiPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: boxHeight)
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(rankColor(level).opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(rankColor(level).opacity(0.35), lineWidth: 1)
        )
    }

    private var rankingTable: some View {
        SkiGlassCard(cornerRadius: 28, padding: 16) {
        VStack(alignment: .leading, spacing: 10) {
            Text(settings.strings.leaderboardFullRank)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(SkiPalette.textPrimary)

            if let error = leaderboardService.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(SkiPalette.red)
            }

            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        Text("#\(entry.rank)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .frame(width: 42)
                            .foregroundStyle(rankColor(entry.rank))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.displayName)
                                .font(.system(size: 14, weight: entry.uid == authService.currentUser?.uid ? .bold : .semibold, design: .rounded))
                                .foregroundStyle(SkiPalette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            if entry.uid == authService.currentUser?.uid {
                                Text(settings.strings.youLabel)
                                    .font(.caption2)
                                    .foregroundStyle(SkiPalette.textSecondary)
                            }
                        }

                        Spacer()

                        Text(scoreText(for: entry))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(SkiPalette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)

                    if entry.id != entries.last?.id {
                        Divider().overlay(SkiPalette.stroke)
                    }
                }
            }
            .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(SkiPalette.stroke, lineWidth: 1)
            )

            Text(leaderboardFooterText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SkiPalette.textSecondary)
        }
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
        case 1: return SkiPalette.yellow
        case 2: return SkiPalette.cyan.opacity(0.75)
        case 3: return SkiPalette.orange
        default: return SkiPalette.textPrimary
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
