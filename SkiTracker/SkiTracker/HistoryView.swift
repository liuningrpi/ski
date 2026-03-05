import SwiftUI
import CoreLocation

// MARK: - Day Group Model

struct DayGroup: Identifiable {
    let id: String // date string as ID
    let date: Date
    let sessions: [TrackSession]

    var totalDistance: Double {
        sessions.reduce(0) { $0 + $1.totalDistanceKm }
    }

    var totalDuration: TimeInterval {
        sessions.reduce(0) { $0 + $1.durationSeconds }
    }

    var totalDescent: Double {
        sessions.reduce(0) { $0 + $1.elevationDrop }
    }

    var maxSpeed: Double {
        sessions.map { $0.maxSpeedKmh }.max() ?? 0
    }

    var avgSpeed: Double {
        guard totalDuration > 0 else { return 0 }
        let totalDistanceM = sessions.reduce(0) { $0 + $1.totalDistanceMeters }
        return (totalDistanceM / totalDuration) * 3.6
    }

    var maxDescentRun: Double {
        sessions.map { $0.elevationDrop }.max() ?? 0
    }

    var fastestRunSpeed: Double {
        sessions.map { $0.maxSpeedKmh }.max() ?? 0
    }

    var longestRunDistance: Double {
        sessions.map { $0.totalDistanceKm }.max() ?? 0
    }

    var avgRunDistance: Double {
        guard sessions.count > 0 else { return 0 }
        return totalDistance / Double(sessions.count)
    }

    var maxAltitude: Double {
        sessions.map { $0.maxAltitude }.max() ?? 0
    }

    var totalDurationFormatted: String {
        let total = Int(totalDuration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - HistoryView

/// Displays all saved sessions grouped by day.
struct HistoryView: View {

    @EnvironmentObject var sessionStore: SessionStore
    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSession: TrackSession?
    @State private var selectedDayGroup: DayGroup?
    @State private var showDeleteAllConfirm = false

    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessionStore.sessions) { session in
            calendar.startOfDay(for: session.startedAt)
        }
        return grouped.map { (date, sessions) in
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            return DayGroup(
                id: dateFormatter.string(from: date),
                date: date,
                sessions: sessions.sorted { $0.startedAt > $1.startedAt }
            )
        }.sorted { $0.date > $1.date }
    }

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            Group {
                if sessionStore.sessions.isEmpty {
                    emptyState
                } else {
                    dayListView
                }
            }
            .navigationTitle(strings.history)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(strings.close) {
                        dismiss()
                    }
                }
                if !sessionStore.sessions.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            showDeleteAllConfirm = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .alert(strings.deleteAllConfirmTitle, isPresented: $showDeleteAllConfirm) {
                Button(strings.cancel, role: .cancel) { }
                Button(strings.delete, role: .destructive) {
                    sessionStore.deleteAll()
                }
            } message: {
                Text(strings.deleteConfirmMessage)
            }
            .sheet(item: $selectedSession) { session in
                SessionDetailView(session: session)
            }
            .sheet(item: $selectedDayGroup) { dayGroup in
                DaySummaryView(dayGroup: dayGroup)
            }
        }
    }

    // MARK: - Day List View

    @ViewBuilder
    private var dayListView: some View {
        let strings = settings.strings
        let units = settings.unitSystem

        List {
            ForEach(dayGroups) { dayGroup in
                Section {
                    // Day summary button
                    Button {
                        selectedDayGroup = dayGroup
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .foregroundColor(.blue)
                            Text(strings.daySummary)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(dayGroup.sessions.count) \(strings.runsCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    // Individual runs
                    ForEach(dayGroup.sessions) { session in
                        Button {
                            selectedSession = session
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(session.startedAt, style: .time)
                                        if let end = session.endedAt {
                                            Text("-")
                                            Text(end, style: .time)
                                        }
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.primary)

                                    Text(session.durationFormatted)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("\(settings.formatDistance(session.totalDistanceKm)) \(units.distanceUnit)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Text("\(settings.formatSpeed(session.maxSpeedKmh)) \(units.speedUnit)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete { offsets in
                        deleteSession(from: dayGroup, at: offsets)
                    }
                } header: {
                    Text(dayGroup.date, style: .date)
                        .font(.headline)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func deleteSession(from dayGroup: DayGroup, at offsets: IndexSet) {
        for index in offsets {
            let session = dayGroup.sessions[index]
            sessionStore.delete(session)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        let strings = settings.strings

        VStack(spacing: 16) {
            Image(systemName: "figure.skiing.downhill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text(strings.noHistory)
                .font(.title3)
                .foregroundColor(.secondary)
            Text(strings.noHistoryMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Day Summary View

struct DaySummaryView: View {

    let dayGroup: DayGroup

    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let strings = settings.strings
        let units = settings.unitSystem

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Date header
                    VStack(spacing: 4) {
                        Text(dayGroup.date, style: .date)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("\(dayGroup.sessions.count) \(strings.runsCount)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)

                    // Summary Stats Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        // Total Distance
                        SummaryCard(
                            icon: "point.topleft.down.to.point.bottomright.curvepath",
                            title: strings.totalDistance,
                            value: settings.formatDistance(dayGroup.totalDistance),
                            unit: units.distanceUnit,
                            color: .blue
                        )

                        // Total Duration
                        SummaryCard(
                            icon: "timer",
                            title: strings.totalDuration,
                            value: dayGroup.totalDurationFormatted,
                            unit: "",
                            color: .green
                        )

                        // Total Descent
                        SummaryCard(
                            icon: "arrow.down.right",
                            title: strings.totalDescent,
                            value: settings.formatAltitude(dayGroup.totalDescent),
                            unit: units.altitudeUnit,
                            color: .orange
                        )

                        // Max Speed
                        SummaryCard(
                            icon: "gauge.with.needle.fill",
                            title: strings.maxSpeedDay,
                            value: settings.formatSpeed(dayGroup.maxSpeed),
                            unit: units.speedUnit,
                            color: .red
                        )

                        // Avg Speed
                        SummaryCard(
                            icon: "speedometer",
                            title: strings.avgSpeedDay,
                            value: settings.formatSpeed(dayGroup.avgSpeed),
                            unit: units.speedUnit,
                            color: .purple
                        )

                        // Max Descent Single Run
                        SummaryCard(
                            icon: "mountain.2.fill",
                            title: strings.maxDescentRun,
                            value: settings.formatAltitude(dayGroup.maxDescentRun),
                            unit: units.altitudeUnit,
                            color: .indigo
                        )

                        // Longest Run
                        SummaryCard(
                            icon: "ruler",
                            title: strings.longestRun,
                            value: settings.formatDistance(dayGroup.longestRunDistance),
                            unit: units.distanceUnit,
                            color: .teal
                        )

                        // Avg Distance per Run
                        SummaryCard(
                            icon: "divide",
                            title: strings.avgRunDistance,
                            value: settings.formatDistance(dayGroup.avgRunDistance),
                            unit: units.distanceUnit,
                            color: .cyan
                        )
                    }
                    .padding(.horizontal)

                    // Max Altitude
                    HStack {
                        Image(systemName: "mountain.2.fill")
                            .foregroundColor(.brown)
                        Text(strings.maxAltitude)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(settings.formatAltitude(dayGroup.maxAltitude)) \(units.altitudeUnit)")
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationTitle(strings.daySummary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(strings.close) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Session Detail View

struct SessionDetailView: View {

    let session: TrackSession

    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let strings = settings.strings
        let units = settings.unitSystem

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Session info header
                    sessionHeader

                    // Segment summary (if available)
                    if !session.segments.isEmpty {
                        segmentSummary
                    }

                    // Map with track polyline
                    let coords = session.points.map { $0.coordinate }
                    TrackMapView(
                        coordinates: coords,
                        followUser: false,
                        showEndMarker: true
                    )
                    .frame(height: 300)
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Statistics
                    StatsView(
                        durationFormatted: session.durationFormatted,
                        distanceKm: session.totalDistanceKm,
                        maxSpeedKmh: session.maxSpeedKmh,
                        avgSpeedKmh: session.avgSpeedKmh,
                        maxAltitude: session.maxAltitude,
                        elevationDrop: session.elevationDrop,
                        pointCount: session.points.count
                    )

                    // Individual runs (if available)
                    if !session.skiingRuns.isEmpty {
                        runsSection
                    }

                    Spacer()
                        .frame(height: 20)
                }
            }
            .navigationTitle(strings.history)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(strings.close) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Segment Summary

    @ViewBuilder
    private var segmentSummary: some View {
        let strings = settings.strings
        let units = settings.unitSystem

        HStack(spacing: 20) {
            // Runs
            VStack {
                HStack(spacing: 4) {
                    Image(systemName: "figure.skiing.downhill")
                        .foregroundColor(.blue)
                    Text("\(session.runCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Text(strings.runsCount)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(height: 40)

            // Lifts
            VStack {
                HStack(spacing: 4) {
                    Image(systemName: "cablecar")
                        .foregroundColor(.orange)
                    Text("\(session.liftCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Text(strings.liftsCompleted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(height: 40)

            // Vertical Drop
            VStack {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .foregroundColor(.green)
                    Text(settings.formatAltitude(session.totalVerticalDrop))
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Text(units.altitudeUnit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Runs Section

    @ViewBuilder
    private var runsSection: some View {
        let strings = settings.strings
        let units = settings.unitSystem

        VStack(alignment: .leading, spacing: 12) {
            Text(strings.runDetails)
                .font(.headline)
                .padding(.horizontal)

            ForEach(Array(session.skiingRuns.enumerated()), id: \.element.id) { index, run in
                HStack {
                    // Run number
                    Text("#\(index + 1)")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        // Time
                        HStack {
                            Text(run.startTime, style: .time)
                            if let end = run.endTime {
                                Text("-")
                                Text(end, style: .time)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        // Duration
                        Text(run.durationFormatted)
                            .font(.subheadline)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        // Distance
                        Text("\(settings.formatDistance(run.totalDistanceKm)) \(units.distanceUnit)")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        // Max Speed
                        Text("\(settings.formatSpeed(run.maxSpeedKmh)) \(units.speedUnit)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Vertical drop
                    VStack(alignment: .trailing) {
                        Text("\(settings.formatAltitude(run.elevationDrop))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(units.altitudeUnit)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 50)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Session Header

    @ViewBuilder
    private var sessionHeader: some View {
        VStack(spacing: 4) {
            Text(session.startedAt, style: .date)
                .font(.headline)
            HStack {
                Text(session.startedAt, style: .time)
                if let end = session.endedAt {
                    Text("-")
                    Text(end, style: .time)
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)

            if let device = session.deviceInfo {
                Text(device)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
        .environmentObject(SessionStore())
}
