import SwiftUI
import CoreLocation
import UIKit

private func segmentStyle(for state: SkiingState) -> TrackMapView.SegmentStyle {
    switch state {
    case .skiing: return .skiing
    case .lift: return .lift
    case .stopped, .idle: return .stopped
    }
}

private func mapSegments(for session: TrackSession) -> [TrackMapView.Segment] {
    let fromSegments = session.segments.compactMap { segment -> TrackMapView.Segment? in
        let coords = segment.points.map(\.coordinate)
        guard coords.count >= 2 else { return nil }
        return TrackMapView.Segment(coordinates: coords, style: segmentStyle(for: segment.type))
    }
    if !fromSegments.isEmpty {
        return fromSegments
    }

    let coords = session.points.map(\.coordinate)
    guard coords.count >= 2 else { return [] }
    return [TrackMapView.Segment(coordinates: coords, style: .skiing)]
}

private func mapSegments(for run: RunSegment) -> [TrackMapView.Segment] {
    let coords = run.points.map(\.coordinate)
    guard coords.count >= 2 else { return [] }
    return [TrackMapView.Segment(coordinates: coords, style: segmentStyle(for: run.type))]
}

private func mapSegments(for dayGroup: DayGroup) -> [TrackMapView.Segment] {
    dayGroup.sessions.flatMap { mapSegments(for: $0) }
}

private func downhillPlaybackPoints(from points: [TrackPoint]) -> [TrackPoint] {
    guard points.count >= 2 else { return points }
    guard let highest = points.enumerated().max(by: { $0.element.altitude < $1.element.altitude }),
          let lowestAfterHighest = points[highest.offset...].enumerated().min(by: { $0.element.altitude < $1.element.altitude }) else {
        return points
    }
    let endIndex = highest.offset + lowestAfterHighest.offset
    if endIndex > highest.offset {
        return Array(points[highest.offset...endIndex])
    }
    return points
}

private func heatmapColorForSpeedMps(_ speedMps: Double) -> UIColor {
    // Cold -> hot palette: blue -> cyan -> green -> yellow -> orange -> red.
    let stops: [(speed: Double, color: UIColor)] = [
        (0.0, UIColor(red: 0.10, green: 0.35, blue: 0.95, alpha: 1)),
        (3.5, UIColor(red: 0.10, green: 0.75, blue: 0.95, alpha: 1)),
        (7.0, UIColor(red: 0.15, green: 0.85, blue: 0.35, alpha: 1)),
        (11.0, UIColor(red: 0.95, green: 0.85, blue: 0.10, alpha: 1)),
        (15.0, UIColor(red: 0.98, green: 0.52, blue: 0.10, alpha: 1)),
        (20.0, UIColor(red: 0.92, green: 0.14, blue: 0.12, alpha: 1))
    ]

    let clamped = min(max(speedMps, stops.first?.speed ?? 0), stops.last?.speed ?? 20)
    for idx in 1..<stops.count {
        let lhs = stops[idx - 1]
        let rhs = stops[idx]
        if clamped <= rhs.speed {
            let t = (clamped - lhs.speed) / max(0.001, (rhs.speed - lhs.speed))
            var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
            var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
            lhs.color.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
            rhs.color.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
            return UIColor(
                red: lr + (rr - lr) * t,
                green: lg + (rg - lg) * t,
                blue: lb + (rb - lb) * t,
                alpha: la + (ra - la) * t
            )
        }
    }
    return stops.last?.color ?? .systemRed
}

private func speedHeatmapSegments(from points: [TrackPoint], lineWidth: CGFloat = 5.0) -> [TrackMapView.Segment] {
    guard points.count >= 2 else { return [] }

    var rawSpeeds = Array(repeating: 0.0, count: points.count - 1)
    for idx in 1..<points.count {
        let prev = points[idx - 1]
        let curr = points[idx]
        if curr.speed >= 0 {
            rawSpeeds[idx - 1] = curr.speed
            continue
        }
        let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
        guard dt > 0 else {
            rawSpeeds[idx - 1] = 0
            continue
        }
        let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
        let currLoc = CLLocation(latitude: curr.latitude, longitude: curr.longitude)
        rawSpeeds[idx - 1] = currLoc.distance(from: prevLoc) / dt
    }

    // EMA smoothing so color transition is natural.
    var smoothSpeeds = rawSpeeds
    let alpha = 0.25
    for idx in 1..<smoothSpeeds.count {
        smoothSpeeds[idx] = alpha * rawSpeeds[idx] + (1 - alpha) * smoothSpeeds[idx - 1]
    }

    var segments: [TrackMapView.Segment] = []
    for idx in 1..<points.count {
        let prev = points[idx - 1]
        let curr = points[idx]
        segments.append(
            TrackMapView.Segment(
                coordinates: [prev.coordinate, curr.coordinate],
                style: .skiing,
                colorOverride: heatmapColorForSpeedMps(smoothSpeeds[idx - 1]),
                lineWidthOverride: lineWidth,
                drawPriorityOverride: 1
            )
        )
    }
    return segments
}

private struct TrackSegmentLegend: View {
    @ObservedObject private var settings = SettingsManager.shared
    var showSkiing: Bool = true
    var showLift: Bool = true

    var body: some View {
        HStack(spacing: 16) {
            if showSkiing {
                HStack(spacing: 6) {
                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                    Text(settings.strings.stateSkiing)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if showLift {
                HStack(spacing: 6) {
                    Circle().fill(Color.yellow).frame(width: 8, height: 8)
                    Text(settings.strings.stateLift)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}

// MARK: - Day Group Model

struct DayGroup: Identifiable {
    let id: String // date string as ID
    let date: Date
    let sessions: [TrackSession]

    var totalDistance: Double {
        sessions.reduce(0) { $0 + $1.totalDistanceKm }
    }

    var runCount: Int {
        sessions.reduce(0) { $0 + $1.runCount }
    }

    var liftCount: Int {
        sessions.reduce(0) { $0 + $1.liftCount }
    }

    var totalDuration: TimeInterval {
        sessions.reduce(0) { $0 + $1.durationSeconds }
    }

    var totalDescent: Double {
        sessions.reduce(0) { $0 + $1.totalVerticalDrop }
    }

    var maxSpeed: Double {
        sessions.map { $0.maxSpeedKmh }.max() ?? 0
    }

    var avgSpeed: Double {
        let runs = sessions.flatMap { $0.skiingRuns }.filter { $0.durationSeconds > 0 }
        guard !runs.isEmpty else { return 0 }
        let weightedSpeed = runs.reduce(0.0) { partial, run in
            partial + (run.avgSpeedKmh * run.durationSeconds)
        }
        let totalRunDuration = runs.reduce(0.0) { $0 + $1.durationSeconds }
        guard totalRunDuration > 0 else { return 0 }
        return weightedSpeed / totalRunDuration
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

    var resortNames: [String] {
        let names = sessions.compactMap { session -> String? in
            let trimmed = session.resortName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty == false) ? trimmed : nil
        }
        return Array(NSOrderedSet(array: names)) as? [String] ?? names
    }

    var resortSummary: String? {
        let names = resortNames
        guard !names.isEmpty else { return nil }
        return names.joined(separator: " · ")
    }
}

struct MonthGroup: Identifiable {
    let id: String
    let monthStart: Date
    let dayGroups: [DayGroup]

    var totalDistance: Double {
        dayGroups.reduce(0) { $0 + $1.totalDistance }
    }

    var runCount: Int {
        dayGroups.reduce(0) { $0 + $1.runCount }
    }

    var liftCount: Int {
        dayGroups.reduce(0) { $0 + $1.liftCount }
    }

    var totalDuration: TimeInterval {
        dayGroups.reduce(0) { $0 + $1.totalDuration }
    }

    var totalDescent: Double {
        dayGroups.reduce(0) { $0 + $1.totalDescent }
    }

    var maxSpeed: Double {
        dayGroups.map { $0.maxSpeed }.max() ?? 0
    }
}

struct YearGroup: Identifiable {
    let id: String
    let yearStart: Date
    let monthGroups: [MonthGroup]

    var totalDistance: Double {
        monthGroups.reduce(0) { $0 + $1.totalDistance }
    }

    var runCount: Int {
        monthGroups.reduce(0) { $0 + $1.runCount }
    }

    var liftCount: Int {
        monthGroups.reduce(0) { $0 + $1.liftCount }
    }

    var totalDuration: TimeInterval {
        monthGroups.reduce(0) { $0 + $1.totalDuration }
    }

    var totalDescent: Double {
        monthGroups.reduce(0) { $0 + $1.totalDescent }
    }

    var maxSpeed: Double {
        monthGroups.map { $0.maxSpeed }.max() ?? 0
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
    @State private var expandedYears: Set<String> = []
    @State private var expandedMonths: Set<String> = []
    @State private var expandedDays: Set<String> = []

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

    private var yearGroups: [YearGroup] {
        let calendar = Calendar.current
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"

        let groupedYears = Dictionary(grouping: dayGroups) { dayGroup in
            calendar.component(.year, from: dayGroup.date)
        }

        return groupedYears.map { year, groups in
            let groupedMonths = Dictionary(grouping: groups) { dayGroup in
                let components = calendar.dateComponents([.year, .month], from: dayGroup.date)
                return calendar.date(from: components) ?? dayGroup.date
            }

            let monthGroups = groupedMonths.map { monthStart, groupedDays in
                MonthGroup(
                    id: monthFormatter.string(from: monthStart),
                    monthStart: monthStart,
                    dayGroups: groupedDays.sorted { $0.date > $1.date }
                )
            }
            .sorted { $0.monthStart > $1.monthStart }

            let yearDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
            return YearGroup(id: yearFormatter.string(from: yearDate), yearStart: yearDate, monthGroups: monthGroups)
        }
        .sorted { $0.yearStart > $1.yearStart }
    }

    private var mostRecentYearID: String? {
        yearGroups.first?.id
    }

    private var mostRecentMonthID: String? {
        yearGroups.first?.monthGroups.first?.id
    }

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            dayListView
                .navigationTitle(strings.history)
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    seedExpansionStateIfNeeded()
                }
                .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(strings.close) {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedSession) { session in
                SessionDetailView(session: session)
                    .environmentObject(sessionStore)
            }
            .sheet(item: $selectedDayGroup) { dayGroup in
                DaySummaryView(dayGroup: dayGroup)
                    .environmentObject(sessionStore)
            }
        }
    }

    // MARK: - Day List View

    @ViewBuilder
    private var dayListView: some View {
        let units = settings.unitSystem

        List {
            if dayGroups.isEmpty {
                Section {
                    emptyState
                }
            }

            ForEach(yearGroups) { yearGroup in
                Section {
                    yearHeader(yearGroup, units: units)

                    if expandedYears.contains(yearGroup.id) {
                        ForEach(yearGroup.monthGroups) { monthGroup in
                            monthSection(monthGroup, units: units)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func sessionRow(session: TrackSession, units: UnitSystem) -> some View {
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                sessionStore.delete(session)
            } label: {
                Label(settings.strings.delete, systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func yearHeader(_ yearGroup: YearGroup, units: UnitSystem) -> some View {
        Button {
            toggleExpansion(of: yearGroup.id, in: &expandedYears)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: expandedYears.contains(yearGroup.id) ? "chevron.down.circle.fill" : "chevron.right.circle")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(yearText(for: yearGroup.yearStart))
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("\(yearGroup.runCount) \(settings.strings.runsCount) · \(yearGroup.monthGroups.count) \(settings.strings.monthsLabel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(settings.formatDistance(yearGroup.totalDistance)) \(units.distanceUnit)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("\(settings.formatSpeed(yearGroup.maxSpeed)) \(units.speedUnit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func monthSection(_ monthGroup: MonthGroup, units: UnitSystem) -> some View {
        VStack(spacing: 8) {
            Button {
                toggleExpansion(of: monthGroup.id, in: &expandedMonths)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: expandedMonths.contains(monthGroup.id) ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(monthText(for: monthGroup.monthStart))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text("\(monthGroup.runCount) \(settings.strings.runsCount) · \(monthGroup.dayGroups.count) \(settings.strings.daysLabel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(settings.formatDistance(monthGroup.totalDistance)) \(units.distanceUnit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            if expandedMonths.contains(monthGroup.id) {
                ForEach(monthGroup.dayGroups) { dayGroup in
                    daySection(dayGroup, units: units)
                }
            }
        }
        .padding(.leading, 8)
    }

    @ViewBuilder
    private func daySection(_ dayGroup: DayGroup, units: UnitSystem) -> some View {
        VStack(spacing: 8) {
            Button {
                toggleExpansion(of: dayGroup.id, in: &expandedDays)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: expandedDays.contains(dayGroup.id) ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dayText(for: dayGroup.date))
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        if let resortSummary = dayGroup.resortSummary {
                            Text(resortSummary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(settings.formatDistance(dayGroup.totalDistance)) \(units.distanceUnit)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text("\(dayGroup.sessions.count) \(settings.strings.sessionsCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            if expandedDays.contains(dayGroup.id) {
                Button {
                    selectedDayGroup = dayGroup
                } label: {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.blue)
                        Text(settings.strings.daySummary)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(dayGroup.runCount) \(settings.strings.runsCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                ForEach(dayGroup.sessions) { session in
                    sessionRow(session: session, units: units)
                }
            }
        }
        .padding(.leading, 20)
    }

    private func seedExpansionStateIfNeeded() {
        guard expandedYears.isEmpty, expandedMonths.isEmpty, expandedDays.isEmpty else { return }
        if let mostRecentYearID {
            expandedYears.insert(mostRecentYearID)
        }
        if let mostRecentMonthID {
            expandedMonths.insert(mostRecentMonthID)
        }
    }

    private func toggleExpansion(of id: String, in set: inout Set<String>) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }

    private func yearText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    private func monthText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date)
    }

    private func dayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
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

// MARK: - Run with Session Reference (for Day Summary)

struct RunWithSession: Identifiable {
    let id: UUID
    let run: RunSegment
    let session: TrackSession
    let runIndex: Int  // 1-based index within the day
}

private struct SessionRunGroup: Identifiable {
    let id: UUID
    let session: TrackSession
    let runs: [RunWithSession]
}

// MARK: - Day Summary View

struct DaySummaryView: View {

    let dayGroup: DayGroup

    @EnvironmentObject var sessionStore: SessionStore
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var dayPlaybackProgress = 0.0
    @State private var isDayPlaybackRunning = false
    @State private var dayPlaybackTimer: Timer?
    @State private var showDeleteDayConfirm = false

    // Extract all skiing runs from all sessions in this day
    private var allRuns: [RunWithSession] {
        var runs: [RunWithSession] = []
        var index = 1
        for session in dayGroup.sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            for run in session.skiingRuns {
                runs.append(RunWithSession(
                    id: run.id,
                    run: run,
                    session: session,
                    runIndex: index
                ))
                index += 1
            }
        }
        return runs
    }

    private var runsGroupedBySession: [SessionRunGroup] {
        let sortedSessions = dayGroup.sessions.sorted(by: { $0.startedAt < $1.startedAt })
        return sortedSessions.compactMap { session in
            let runs = allRuns.filter { $0.session.id == session.id }
            guard !runs.isEmpty else { return nil }
            return SessionRunGroup(id: session.id, session: session, runs: runs)
        }
    }

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
                        Text("\(dayGroup.runCount) \(strings.runsCount)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)

                    let daySegments = dayHeatmapSegments
                    if !daySegments.isEmpty {
                        TrackMapView(
                            segments: daySegments,
                            followUser: false,
                            showEndMarker: false,
                            playbackCoordinate: dayPlaybackCurrentPoint?.coordinate,
                            playbackInitials: playbackUserInitials,
                            playbackPhotoURL: playbackUserPhotoURL
                        )
                        .frame(height: 250)
                        .cornerRadius(12)
                        .padding(.horizontal)

                        dayPlaybackControlCard
                            .padding(.horizontal)
                    }

                    HStack(spacing: 20) {
                        VStack {
                            HStack(spacing: 4) {
                                Image(systemName: "figure.skiing.downhill")
                                    .foregroundColor(.blue)
                                Text("\(dayGroup.runCount)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            Text(strings.runsCount)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Divider().frame(height: 40)

                        VStack {
                            HStack(spacing: 4) {
                                Image(systemName: "cablecar")
                                    .foregroundColor(.yellow)
                                Text("\(dayGroup.liftCount)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            Text(strings.liftsCompleted)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

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

                    // Individual Runs List
                    if !allRuns.isEmpty {
                        runsListSection
                    }

                    Spacer()
                        .frame(height: 20)
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteDayConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .confirmationDialog(settings.strings.deleteAllConfirmTitle, isPresented: $showDeleteDayConfirm, titleVisibility: .visible) {
                Button(settings.strings.delete, role: .destructive) {
                    deleteDay()
                }
                Button(settings.strings.cancel, role: .cancel) { }
            } message: {
                Text(settings.strings.deleteConfirmMessage)
            }
        }
        .onDisappear {
            stopDayPlaybackTimer()
        }
    }

    private func deleteDay() {
        for session in dayGroup.sessions {
            sessionStore.delete(session)
        }
        dismiss()
    }

    // MARK: - Runs List Section

    @ViewBuilder
    private var runsListSection: some View {
        let strings = settings.strings

        VStack(alignment: .leading, spacing: 12) {
            Text(strings.runDetails)
                .font(.headline)
                .padding(.horizontal)

            ForEach(runsGroupedBySession) { group in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary)
                        Text(sessionWindow(group.session))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(group.runs.count) \(strings.runsCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    ForEach(Array(group.runs.enumerated()), id: \.element.id) { idx, runWithSession in
                        NavigationLink {
                            RunDetailView(
                                run: runWithSession.run,
                                runIndex: runWithSession.runIndex,
                                onDelete: {
                                    deleteRun(runWithSession)
                                }
                            )
                        } label: {
                            runRow(
                                number: runWithSession.runIndex,
                                run: runWithSession.run,
                                units: settings.unitSystem,
                                embedded: true
                            )
                        }
                        .buttonStyle(.plain)

                        if idx < group.runs.count - 1 {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func runRow(number: Int, run: RunSegment, units: UnitSystem, embedded: Bool = false) -> some View {
        HStack {
            Text("#\(number)")
                .font(.headline)
                .foregroundColor(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(run.startTime, style: .time)
                    if let end = run.endTime {
                        Text("-")
                        Text(end, style: .time)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Text(run.durationFormatted)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(settings.formatDistance(run.totalDistanceKm)) \(units.distanceUnit)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("\(settings.formatSpeed(run.maxSpeedKmh)) \(units.speedUnit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .trailing) {
                Text("\(settings.formatAltitude(run.elevationDrop))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(units.altitudeUnit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 50)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, embedded ? 12 : 16)
        .padding(.vertical, embedded ? 12 : 14)
        .background(embedded ? Color.clear : Color(.systemGray6))
        .cornerRadius(10)
    }

    private func sessionWindow(_ session: TrackSession) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let start = formatter.string(from: session.startedAt)
        if let end = session.endedAt {
            return "\(start) - \(formatter.string(from: end))"
        }
        return start
    }

    private func deleteRun(_ runWithSession: RunWithSession) {
        var session = runWithSession.session
        session.deleteRun(id: runWithSession.run.id)
        sessionStore.update(session)
    }

    private var dayPlaybackPoints: [TrackPoint] {
        allRuns
            .sorted { $0.run.startTime < $1.run.startTime }
            .flatMap { downhillPlaybackPoints(from: $0.run.points) }
    }

    private var dayHeatmapSegments: [TrackMapView.Segment] {
        speedHeatmapSegments(from: dayPlaybackPoints, lineWidth: 5.5)
    }

    private var dayPlaybackCurrentPoint: TrackPoint? {
        guard !dayPlaybackPoints.isEmpty else { return nil }
        let maxIndex = Double(dayPlaybackPoints.count - 1)
        let clamped = min(max(0, dayPlaybackProgress), maxIndex)
        return interpolatedDayPlaybackPoint(at: clamped)
    }

    private var dayPlaybackElapsedTime: TimeInterval {
        guard !dayPlaybackPoints.isEmpty else { return 0 }
        let maxIndex = Double(dayPlaybackPoints.count - 1)
        let clamped = min(max(0, dayPlaybackProgress), maxIndex)
        let lower = Int(floor(clamped))
        let upper = Int(ceil(clamped))
        guard upper < dayPlaybackPoints.count else {
            return dayPlaybackPoints[lower].timestamp.timeIntervalSince(dayGroup.date)
        }
        let t = clamped - Double(lower)
        let start = dayPlaybackPoints[lower].timestamp.timeIntervalSince(dayGroup.date)
        let end = dayPlaybackPoints[upper].timestamp.timeIntervalSince(dayGroup.date)
        return start + (end - start) * t
    }

    private var dayPlaybackSpeedKmh: Double {
        guard let point = dayPlaybackCurrentPoint else { return 0 }
        if point.speed >= 0 {
            return point.speed * 3.6
        }
        guard dayPlaybackPoints.count >= 2 else { return 0 }
        let idx = min(max(1, Int(round(dayPlaybackProgress))), dayPlaybackPoints.count - 1)
        let prev = dayPlaybackPoints[idx - 1]
        let curr = dayPlaybackPoints[idx]
        let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
        guard dt > 0 else { return 0 }
        let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
        let currLoc = CLLocation(latitude: curr.latitude, longitude: curr.longitude)
        return (currLoc.distance(from: prevLoc) / dt) * 3.6
    }

    private var dayPlaybackAltitudeM: Double {
        dayPlaybackCurrentPoint?.altitude ?? 0
    }

    private var playbackUserInitials: String {
        let base = authService.currentUser?.displayName ?? authService.currentUser?.email ?? settings.strings.youLabel
        let parts = base
            .split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" || $0 == "." })
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts.prefix(2).compactMap { $0.first }).uppercased()
        }
        if let first = parts.first?.first {
            return String(first).uppercased()
        }
        return String(settings.strings.youLabel.prefix(1)).uppercased()
    }

    private var playbackUserPhotoURL: URL? {
        guard let raw = authService.currentUser?.photoURL, let url = URL(string: raw) else {
            return nil
        }
        return url
    }

    @ViewBuilder
    private var dayPlaybackControlCard: some View {
        let strings = settings.strings
        let units = settings.unitSystem

        VStack(spacing: 10) {
            HStack {
                Text(strings.dayPlayback)
                    .font(.headline)
                Spacer()
                Button {
                    if isDayPlaybackRunning {
                        stopDayPlaybackTimer()
                    } else {
                        startDayPlayback()
                    }
                } label: {
                    Label(isDayPlaybackRunning ? strings.pause : strings.play, systemImage: isDayPlaybackRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    resetDayPlayback()
                } label: {
                    Label(strings.reset, systemImage: "gobackward")
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Label(formattedElapsed(dayPlaybackElapsedTime), systemImage: "clock")
                Spacer()
                Label("\(settings.formatSpeed(dayPlaybackSpeedKmh)) \(units.speedUnit)", systemImage: "speedometer")
                Spacer()
                Label("\(settings.formatAltitude(dayPlaybackAltitudeM)) \(units.altitudeUnit)", systemImage: "mountain.2.fill")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)

            if dayPlaybackPoints.count > 1 {
                Slider(
                    value: Binding(
                        get: { dayPlaybackProgress },
                        set: { dayPlaybackProgress = $0 }
                    ),
                    in: 0...Double(dayPlaybackPoints.count - 1)
                )
                .tint(.blue)
            } else {
                Text(strings.noTrackData)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func startDayPlayback() {
        guard dayPlaybackPoints.count > 1 else { return }
        let maxProgress = Double(dayPlaybackPoints.count - 1)
        if dayPlaybackProgress >= maxProgress {
            dayPlaybackProgress = 0
        }
        stopDayPlaybackTimer()
        isDayPlaybackRunning = true
        let tick = 1.0 / 30.0
        let targetDuration = min(30.0, max(10.0, Double(dayPlaybackPoints.count) * 0.05))
        let progressStep = maxProgress * (tick / targetDuration)
        dayPlaybackTimer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { _ in
            if dayPlaybackProgress < maxProgress {
                dayPlaybackProgress = min(maxProgress, dayPlaybackProgress + progressStep)
            } else {
                stopDayPlaybackTimer()
            }
        }
    }

    private func resetDayPlayback() {
        stopDayPlaybackTimer()
        dayPlaybackProgress = 0
    }

    private func stopDayPlaybackTimer() {
        dayPlaybackTimer?.invalidate()
        dayPlaybackTimer = nil
        isDayPlaybackRunning = false
    }

    private func interpolatedDayPlaybackPoint(at progress: Double) -> TrackPoint? {
        guard !dayPlaybackPoints.isEmpty else { return nil }
        let maxIndex = Double(dayPlaybackPoints.count - 1)
        let clamped = min(max(0, progress), maxIndex)
        let lower = Int(floor(clamped))
        let upper = Int(ceil(clamped))
        guard upper < dayPlaybackPoints.count, lower != upper else {
            return dayPlaybackPoints[lower]
        }

        let from = dayPlaybackPoints[lower]
        let to = dayPlaybackPoints[upper]
        let t = clamped - Double(lower)
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        let fromTs = from.timestamp.timeIntervalSince1970
        let toTs = to.timestamp.timeIntervalSince1970

        return TrackPoint(
            latitude: lerp(from.latitude, to.latitude),
            longitude: lerp(from.longitude, to.longitude),
            altitude: lerp(from.altitude, to.altitude),
            horizontalAccuracy: lerp(from.horizontalAccuracy, to.horizontalAccuracy),
            verticalAccuracy: lerp(from.verticalAccuracy, to.verticalAccuracy),
            speed: from.speed >= 0 ? lerp(from.speed, to.speed) : -1,
            course: from.course >= 0 ? lerp(from.course, to.course) : -1,
            timestamp: Date(timeIntervalSince1970: lerp(fromTs, toTs))
        )
    }

    private func formattedElapsed(_ interval: TimeInterval) -> String {
        let clamped = max(0, Int(interval.rounded()))
        let minutes = clamped / 60
        let seconds = clamped % 60
        return String(format: "%02d:%02d", minutes, seconds)
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

    @State var session: TrackSession
    @EnvironmentObject var sessionStore: SessionStore

    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteSessionConfirm = false
    @State private var sessionHeartRateStats = HeartRateStats(maxBPM: nil, avgBPM: nil)
    @State private var singleRunHeartRateStats = HeartRateStats(maxBPM: nil, avgBPM: nil)
    @State private var sessionPlaybackProgress = 0.0
    @State private var isSessionPlaybackRunning = false
    @State private var sessionPlaybackTimer: Timer?

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    let sessionSegments = mapSegments(for: session)
                    if !sessionSegments.isEmpty {
                        let hasLift = sessionSegments.contains { $0.style == .lift }
                        TrackMapView(
                            segments: sessionSegments,
                            followUser: false,
                            showEndMarker: false,
                            playbackCoordinate: sessionPlaybackCurrentPoint?.coordinate,
                            playbackInitials: sessionPlaybackUserInitials,
                            playbackPhotoURL: sessionPlaybackUserPhotoURL
                        )
                        .frame(height: 300)
                        .cornerRadius(12)
                        .padding(.horizontal)
                        TrackSegmentLegend(showSkiing: true, showLift: hasLift)
                        sessionPlaybackControlCard
                            .padding(.horizontal)
                    }

                    if session.skiingRuns.count == 1, let run = session.skiingRuns.first {
                        singleRunDetailsSection(run: run)
                    } else if !session.skiingRuns.isEmpty {
                        // Session-level summary is shown only for multi-run sessions.
                        sessionHeader
                        if !session.segments.isEmpty {
                            segmentSummary
                        }
                        StatsView(
                            durationFormatted: session.durationFormatted,
                            distanceKm: session.totalDistanceKm,
                            maxSpeedKmh: session.maxSpeedKmh,
                            avgSpeedKmh: session.avgSpeedKmh,
                            maxAltitude: session.maxAltitude,
                            elevationDrop: session.elevationDrop,
                            pointCount: session.points.count,
                            showHeartRate: true,
                            maxHeartRateBPM: sessionHeartRateStats.maxBPM,
                            avgHeartRateBPM: sessionHeartRateStats.avgBPM
                        )
                        // Individual runs (if available)
                        runsSection
                    }

                    Spacer()
                        .frame(height: 20)
                }
            }
            .navigationTitle(session.skiingRuns.count == 1 ? strings.runDetails : strings.history)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(strings.close) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteSessionConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .confirmationDialog(strings.deleteConfirmTitle, isPresented: $showDeleteSessionConfirm, titleVisibility: .visible) {
                Button(strings.delete, role: .destructive) {
                    deleteSession()
                }
                Button(strings.cancel, role: .cancel) { }
            } message: {
                Text(strings.deleteConfirmMessage)
            }
            .task(id: session.id) {
                sessionPlaybackProgress = 0
                if session.needsRemoteTrackHydration, let user = authService.currentUser,
                   let hydrated = await FirestoreService.shared.hydrateSessionTrack(session, uid: user.uid) {
                    await MainActor.run {
                        session = hydrated
                    }
                }
                await loadSessionHeartRate()
                if let run = session.skiingRuns.first, session.skiingRuns.count == 1 {
                    await loadSingleRunHeartRate(run: run)
                } else {
                    await MainActor.run {
                        singleRunHeartRateStats = HeartRateStats(maxBPM: nil, avgBPM: nil)
                    }
                }
            }
        }
        .onDisappear {
            stopSessionPlaybackTimer()
        }
    }

    private func deleteRun(_ run: RunSegment) {
        session.deleteRun(id: run.id)
        sessionStore.update(session)
    }

    private func deleteSession() {
        sessionStore.delete(session)
        dismiss()
    }

    private func loadSessionHeartRate() async {
        guard let end = session.endedAt else {
            await MainActor.run {
                sessionHeartRateStats = HeartRateStats(maxBPM: nil, avgBPM: nil)
            }
            return
        }

        let stats = await HeartRateService.shared.fetchStats(start: session.startedAt, end: end)
        await MainActor.run {
            sessionHeartRateStats = stats
        }
    }

    private func loadSingleRunHeartRate(run: RunSegment) async {
        guard let end = run.endTime else {
            await MainActor.run {
                singleRunHeartRateStats = HeartRateStats(maxBPM: nil, avgBPM: nil)
            }
            return
        }

        let stats = await HeartRateService.shared.fetchStats(start: run.startTime, end: end)
        await MainActor.run {
            singleRunHeartRateStats = stats
        }
    }

    private var sessionPlaybackPoints: [TrackPoint] {
        if session.points.count >= 2 {
            return session.points.sorted { $0.timestamp < $1.timestamp }
        }
        let fromSegments = session.segments
            .sorted { $0.startTime < $1.startTime }
            .flatMap { $0.points }
        return fromSegments.sorted { $0.timestamp < $1.timestamp }
    }

    private var sessionPlaybackCurrentPoint: TrackPoint? {
        guard !sessionPlaybackPoints.isEmpty else { return nil }
        let maxIndex = Double(sessionPlaybackPoints.count - 1)
        let clamped = min(max(0, sessionPlaybackProgress), maxIndex)
        return interpolatedSessionPlaybackPoint(at: clamped)
    }

    private var sessionPlaybackElapsedTime: TimeInterval {
        guard !sessionPlaybackPoints.isEmpty else { return 0 }
        let maxIndex = Double(sessionPlaybackPoints.count - 1)
        let clamped = min(max(0, sessionPlaybackProgress), maxIndex)
        let lower = Int(floor(clamped))
        let upper = Int(ceil(clamped))
        guard upper < sessionPlaybackPoints.count else {
            return sessionPlaybackPoints[lower].timestamp.timeIntervalSince(session.startedAt)
        }
        let t = clamped - Double(lower)
        let start = sessionPlaybackPoints[lower].timestamp.timeIntervalSince(session.startedAt)
        let end = sessionPlaybackPoints[upper].timestamp.timeIntervalSince(session.startedAt)
        return start + (end - start) * t
    }

    private var sessionPlaybackSpeedKmh: Double {
        guard let point = sessionPlaybackCurrentPoint else { return 0 }
        if point.speed >= 0 {
            return point.speed * 3.6
        }
        guard sessionPlaybackPoints.count >= 2 else { return 0 }
        let idx = min(max(1, Int(round(sessionPlaybackProgress))), sessionPlaybackPoints.count - 1)
        let prev = sessionPlaybackPoints[idx - 1]
        let curr = sessionPlaybackPoints[idx]
        let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
        guard dt > 0 else { return 0 }
        let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
        let currLoc = CLLocation(latitude: curr.latitude, longitude: curr.longitude)
        return (currLoc.distance(from: prevLoc) / dt) * 3.6
    }

    private var sessionPlaybackAltitudeM: Double {
        sessionPlaybackCurrentPoint?.altitude ?? 0
    }

    private var sessionPlaybackUserInitials: String {
        let base = authService.currentUser?.displayName ?? authService.currentUser?.email ?? settings.strings.youLabel
        let parts = base
            .split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" || $0 == "." })
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts.prefix(2).compactMap { $0.first }).uppercased()
        }
        if let first = parts.first?.first {
            return String(first).uppercased()
        }
        return String(settings.strings.youLabel.prefix(1)).uppercased()
    }

    private var sessionPlaybackUserPhotoURL: URL? {
        guard let raw = authService.currentUser?.photoURL, let url = URL(string: raw) else {
            return nil
        }
        return url
    }

    @ViewBuilder
    private var sessionPlaybackControlCard: some View {
        let strings = settings.strings
        let units = settings.unitSystem

        VStack(spacing: 10) {
            HStack {
                Text(strings.sessionPlayback)
                    .font(.headline)
                Spacer()
                Button {
                    if isSessionPlaybackRunning {
                        stopSessionPlaybackTimer()
                    } else {
                        startSessionPlayback()
                    }
                } label: {
                    Label(isSessionPlaybackRunning ? strings.pause : strings.play, systemImage: isSessionPlaybackRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    resetSessionPlayback()
                } label: {
                    Label(strings.reset, systemImage: "gobackward")
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Label(formattedElapsed(sessionPlaybackElapsedTime), systemImage: "clock")
                Spacer()
                Label("\(settings.formatSpeed(sessionPlaybackSpeedKmh)) \(units.speedUnit)", systemImage: "speedometer")
                Spacer()
                Label("\(settings.formatAltitude(sessionPlaybackAltitudeM)) \(units.altitudeUnit)", systemImage: "mountain.2.fill")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)

            if sessionPlaybackPoints.count > 1 {
                Slider(
                    value: Binding(
                        get: { sessionPlaybackProgress },
                        set: { sessionPlaybackProgress = $0 }
                    ),
                    in: 0...Double(sessionPlaybackPoints.count - 1)
                )
                .tint(.blue)
            } else {
                Text(strings.noTrackData)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func startSessionPlayback() {
        guard sessionPlaybackPoints.count > 1 else { return }
        let maxProgress = Double(sessionPlaybackPoints.count - 1)
        if sessionPlaybackProgress >= maxProgress {
            sessionPlaybackProgress = 0
        }
        stopSessionPlaybackTimer()
        isSessionPlaybackRunning = true
        let tick = 1.0 / 30.0
        let targetDuration = min(25.0, max(8.0, Double(sessionPlaybackPoints.count) * 0.05))
        let progressStep = maxProgress * (tick / targetDuration)
        sessionPlaybackTimer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { _ in
            if sessionPlaybackProgress < maxProgress {
                sessionPlaybackProgress = min(maxProgress, sessionPlaybackProgress + progressStep)
            } else {
                stopSessionPlaybackTimer()
            }
        }
    }

    private func resetSessionPlayback() {
        stopSessionPlaybackTimer()
        sessionPlaybackProgress = 0
    }

    private func stopSessionPlaybackTimer() {
        sessionPlaybackTimer?.invalidate()
        sessionPlaybackTimer = nil
        isSessionPlaybackRunning = false
    }

    private func interpolatedSessionPlaybackPoint(at progress: Double) -> TrackPoint? {
        guard !sessionPlaybackPoints.isEmpty else { return nil }
        let maxIndex = Double(sessionPlaybackPoints.count - 1)
        let clamped = min(max(0, progress), maxIndex)
        let lower = Int(floor(clamped))
        let upper = Int(ceil(clamped))
        guard upper < sessionPlaybackPoints.count, lower != upper else {
            return sessionPlaybackPoints[lower]
        }

        let from = sessionPlaybackPoints[lower]
        let to = sessionPlaybackPoints[upper]
        let t = clamped - Double(lower)
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        let fromTs = from.timestamp.timeIntervalSince1970
        let toTs = to.timestamp.timeIntervalSince1970

        return TrackPoint(
            latitude: lerp(from.latitude, to.latitude),
            longitude: lerp(from.longitude, to.longitude),
            altitude: lerp(from.altitude, to.altitude),
            horizontalAccuracy: lerp(from.horizontalAccuracy, to.horizontalAccuracy),
            verticalAccuracy: lerp(from.verticalAccuracy, to.verticalAccuracy),
            speed: from.speed >= 0 ? lerp(from.speed, to.speed) : -1,
            course: from.course >= 0 ? lerp(from.course, to.course) : -1,
            timestamp: Date(timeIntervalSince1970: lerp(fromTs, toTs))
        )
    }

    private func formattedElapsed(_ interval: TimeInterval) -> String {
        let clamped = max(0, Int(interval.rounded()))
        let minutes = clamped / 60
        let seconds = clamped % 60
        return String(format: "%02d:%02d", minutes, seconds)
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

    @ViewBuilder
    private func singleRunDetailsSection(run: RunSegment) -> some View {
        let strings = settings.strings
        let units = settings.unitSystem

        VStack(spacing: 12) {
            RunMetricCard(
                icon: "timer",
                title: strings.timeTitle,
                rows: [
                    (strings.runLabel, "#1"),
                    (strings.duration, run.durationFormatted),
                    (strings.windowLabel, runTimeWindow(run))
                ]
            )

            RunMetricCard(
                icon: "point.topleft.down.to.point.bottomright.curvepath",
                title: strings.distance,
                rows: [
                    (strings.distance, "\(settings.formatDistance(run.totalDistanceKm)) \(units.distanceUnit)"),
                    (strings.elevationDrop, "\(settings.formatAltitude(run.elevationDrop)) \(units.altitudeUnit)"),
                    (strings.trackPoints, "\(run.points.count) \(strings.points)")
                ]
            )

            RunMetricCard(
                icon: "gauge.with.needle.fill",
                title: strings.speedTitle,
                rows: [
                    (strings.maxSpeed, "\(settings.formatSpeed(run.maxSpeedKmh)) \(units.speedUnit)"),
                    (strings.avgSpeed, "\(settings.formatSpeed(run.avgSpeedKmh)) \(units.speedUnit)")
                ]
            )

            RunMetricCard(
                icon: "mountain.2.fill",
                title: strings.altitudeTitle,
                rows: [
                    (strings.startAltitude, "\(settings.formatAltitude(run.startAltitude)) \(units.altitudeUnit)"),
                    (strings.endAltitude, "\(settings.formatAltitude(run.endAltitude)) \(units.altitudeUnit)")
                ]
            )

            RunMetricCard(
                icon: "heart.fill",
                title: strings.heartRateTitle,
                rows: [
                    (strings.maxHeartRate, "\(heartRateValue(singleRunHeartRateStats.maxBPM)) \(strings.heartRateUnit)"),
                    (strings.avgHeartRate, "\(heartRateValue(singleRunHeartRateStats.avgBPM)) \(strings.heartRateUnit)")
                ]
            )
        }
        .padding(.horizontal)
    }

    private func runTimeWindow(_ run: RunSegment) -> String {
        var text = formattedTime(run.startTime)
        if let end = run.endTime {
            text += " - \(formattedTime(end))"
        }
        return text
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func heartRateValue(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f", value)
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
                NavigationLink {
                    RunDetailView(
                        run: run,
                        runIndex: index + 1,
                        onDelete: {
                            deleteRun(run)
                        }
                    )
                } label: {
                    HStack {
                        Text("#\(index + 1)")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(run.startTime, style: .time)
                                if let end = run.endTime {
                                    Text("-")
                                    Text(end, style: .time)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)

                            Text(run.durationFormatted)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(settings.formatDistance(run.totalDistanceKm)) \(units.distanceUnit)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text("\(settings.formatSpeed(run.maxSpeedKmh)) \(units.speedUnit)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .trailing) {
                            Text("\(settings.formatAltitude(run.elevationDrop))")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text(units.altitudeUnit)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 50)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
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

// MARK: - Run Detail View

struct RunDetailView: View {

    let run: RunSegment
    let runIndex: Int
    let onDelete: () -> Void

    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false
    @State private var heartRateStats = HeartRateStats(maxBPM: nil, avgBPM: nil)
    @State private var playbackProgress = 0.0
    @State private var isPlaybackRunning = false
    @State private var playbackTimer: Timer?

    var body: some View {
        let strings = settings.strings
        let units = settings.unitSystem

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    let runSegments = heatmapSegmentsForPlayback
                    if !runSegments.isEmpty {
                        TrackMapView(
                            segments: runSegments,
                            followUser: false,
                            showEndMarker: false,
                            playbackCoordinate: playbackCoordinate,
                            playbackInitials: playbackUserInitials,
                            playbackPhotoURL: playbackUserPhotoURL
                        )
                        .frame(height: 280)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    playbackControlCard
                        .padding(.horizontal)

                    RunMetricCard(
                        icon: "timer",
                        title: strings.timeTitle,
                        rows: [
                            (strings.runLabel, "#\(runIndex)"),
                            (strings.duration, run.durationFormatted),
                            (strings.windowLabel, runTimeWindow)
                        ]
                    )
                    .padding(.horizontal)

                    RunMetricCard(
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        title: strings.distance,
                        rows: [
                            (strings.distance, "\(settings.formatDistance(run.totalDistanceKm)) \(units.distanceUnit)"),
                            (strings.elevationDrop, "\(settings.formatAltitude(run.elevationDrop)) \(units.altitudeUnit)"),
                            (strings.trackPoints, "\(run.points.count) \(strings.points)")
                        ]
                    )
                    .padding(.horizontal)

                    RunMetricCard(
                        icon: "gauge.with.needle.fill",
                        title: strings.speedTitle,
                        rows: [
                            (strings.maxSpeed, "\(settings.formatSpeed(run.maxSpeedKmh)) \(units.speedUnit)"),
                            (strings.avgSpeed, "\(settings.formatSpeed(run.avgSpeedKmh)) \(units.speedUnit)")
                        ]
                    )
                    .padding(.horizontal)

                    RunMetricCard(
                        icon: "mountain.2.fill",
                        title: strings.altitudeTitle,
                        rows: [
                            (strings.startAltitude, "\(settings.formatAltitude(run.startAltitude)) \(units.altitudeUnit)"),
                            (strings.endAltitude, "\(settings.formatAltitude(run.endAltitude)) \(units.altitudeUnit)")
                        ]
                    )
                    .padding(.horizontal)

                    RunMetricCard(
                        icon: "heart.fill",
                        title: strings.heartRateTitle,
                        rows: [
                            (strings.maxHeartRate, "\(heartRateValue(heartRateStats.maxBPM)) \(strings.heartRateUnit)"),
                            (strings.avgHeartRate, "\(heartRateValue(heartRateStats.avgBPM)) \(strings.heartRateUnit)")
                        ]
                    )
                    .padding(.horizontal)

                    Spacer().frame(height: 16)
                }
            }
            .navigationTitle(strings.runDetails)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .alert(strings.deleteRunConfirmTitle, isPresented: $showDeleteConfirm) {
            Button(strings.cancel, role: .cancel) { }
            Button(strings.delete, role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text(strings.deleteRunConfirmMessage)
        }
        .task(id: run.id) {
            playbackProgress = 0
            await loadHeartRate()
        }
        .onDisappear {
            stopPlaybackTimer()
        }
    }

    private func loadHeartRate() async {
        guard let end = run.endTime else {
            await MainActor.run {
                heartRateStats = HeartRateStats(maxBPM: nil, avgBPM: nil)
            }
            return
        }

        let stats = await HeartRateService.shared.fetchStats(start: run.startTime, end: end)
        await MainActor.run {
            heartRateStats = stats
        }
    }

    private func heartRateValue(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f", value)
    }

    private var runTimeWindow: String {
        var text = "\(formattedClockTime(run.startTime))"
        if let end = run.endTime {
            text += " - \(formattedClockTime(end))"
        }
        return text
    }

    private var playbackTrackPoints: [TrackPoint] {
        downhillPlaybackPoints(from: run.points)
    }

    private var playbackCurrentPoint: TrackPoint? {
        guard !playbackTrackPoints.isEmpty else { return nil }
        let maxIndex = Double(playbackTrackPoints.count - 1)
        let clamped = min(max(0, playbackProgress), maxIndex)
        return interpolatedPlaybackPoint(at: clamped)
    }

    @ViewBuilder
    private var playbackControlCard: some View {
        let strings = settings.strings
        let units = settings.unitSystem

        VStack(spacing: 10) {
            HStack {
                Text(strings.runPlayback)
                    .font(.headline)
                Spacer()
                Button {
                    if isPlaybackRunning {
                        stopPlaybackTimer()
                    } else {
                        startPlayback()
                    }
                } label: {
                    Label(
                        isPlaybackRunning ? strings.pause : strings.play,
                        systemImage: isPlaybackRunning ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)

                Button {
                    resetPlayback()
                } label: {
                    Label(strings.reset, systemImage: "gobackward")
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Label(playbackTimeText, systemImage: "clock")
                Spacer()
                Label("\(settings.formatSpeed(playbackSpeedKmh)) \(units.speedUnit)", systemImage: "speedometer")
                Spacer()
                Label("\(settings.formatAltitude(playbackAltitudeM)) \(units.altitudeUnit)", systemImage: "mountain.2.fill")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)

            if playbackTrackPoints.count > 1 {
                Slider(
                    value: Binding(
                        get: { playbackProgress },
                        set: { playbackProgress = $0 }
                    ),
                    in: 0...Double(playbackTrackPoints.count - 1)
                )
                .tint(.blue)
            } else {
                Text(strings.noTrackData)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var playbackTimeText: String {
        return formattedElapsed(playbackElapsedTime)
    }

    private var playbackAltitudeM: Double {
        playbackCurrentPoint?.altitude ?? 0
    }

    private var playbackSpeedKmh: Double {
        guard let point = playbackCurrentPoint else { return 0 }
        if point.speed >= 0 {
            return point.speed * 3.6
        }
        return derivedPlaybackSpeedKmh()
    }

    private var playbackCoordinate: CLLocationCoordinate2D? {
        playbackCurrentPoint?.coordinate
    }

    private var playbackElapsedTime: TimeInterval {
        guard !playbackTrackPoints.isEmpty else { return 0 }
        let maxIndex = Double(playbackTrackPoints.count - 1)
        let clamped = min(max(0, playbackProgress), maxIndex)
        let lower = Int(floor(clamped))
        let upper = Int(ceil(clamped))
        guard upper < playbackTrackPoints.count else {
            return playbackTrackPoints[lower].timestamp.timeIntervalSince(run.startTime)
        }
        let t = clamped - Double(lower)
        let start = playbackTrackPoints[lower].timestamp.timeIntervalSince(run.startTime)
        let end = playbackTrackPoints[upper].timestamp.timeIntervalSince(run.startTime)
        return start + (end - start) * t
    }

    private var playbackUserInitials: String {
        let base = authService.currentUser?.displayName ?? authService.currentUser?.email ?? settings.strings.youLabel
        let parts = base
            .split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" || $0 == "." })
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts.prefix(2).compactMap { $0.first }).uppercased()
        }
        if let first = parts.first?.first {
            return String(first).uppercased()
        }
        return String(settings.strings.youLabel.prefix(1)).uppercased()
    }

    private var playbackUserPhotoURL: URL? {
        guard let raw = authService.currentUser?.photoURL, let url = URL(string: raw) else {
            return nil
        }
        return url
    }

    private func derivedPlaybackSpeedKmh() -> Double {
        guard playbackTrackPoints.count >= 2 else { return 0 }
        let idx = min(max(1, Int(round(playbackProgress))), playbackTrackPoints.count - 1)
        let prev = playbackTrackPoints[idx - 1]
        let curr = playbackTrackPoints[idx]
        let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
        guard dt > 0 else { return 0 }
        let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
        let currLoc = CLLocation(latitude: curr.latitude, longitude: curr.longitude)
        return (currLoc.distance(from: prevLoc) / dt) * 3.6
    }

    private func startPlayback() {
        guard playbackTrackPoints.count > 1 else { return }
        let maxProgress = Double(playbackTrackPoints.count - 1)
        if playbackProgress >= maxProgress {
            playbackProgress = 0
        }
        stopPlaybackTimer()
        isPlaybackRunning = true
        let tick = 1.0 / 30.0
        let targetDuration = min(18.0, max(6.0, Double(playbackTrackPoints.count) * 0.07))
        let progressStep = maxProgress * (tick / targetDuration)
        playbackTimer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { _ in
            if playbackProgress < maxProgress {
                playbackProgress = min(maxProgress, playbackProgress + progressStep)
            } else {
                stopPlaybackTimer()
            }
        }
    }

    private func resetPlayback() {
        stopPlaybackTimer()
        playbackProgress = 0
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaybackRunning = false
    }

    private func formattedElapsed(_ interval: TimeInterval) -> String {
        let clamped = max(0, Int(interval.rounded()))
        let minutes = clamped / 60
        let seconds = clamped % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formattedClockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var heatmapSegmentsForPlayback: [TrackMapView.Segment] {
        speedHeatmapSegments(from: playbackTrackPoints, lineWidth: 5)
    }

    private func interpolatedPlaybackPoint(at progress: Double) -> TrackPoint? {
        guard !playbackTrackPoints.isEmpty else { return nil }
        let maxIndex = Double(playbackTrackPoints.count - 1)
        let clamped = min(max(0, progress), maxIndex)
        let lower = Int(floor(clamped))
        let upper = Int(ceil(clamped))
        guard upper < playbackTrackPoints.count, lower != upper else {
            return playbackTrackPoints[lower]
        }

        let from = playbackTrackPoints[lower]
        let to = playbackTrackPoints[upper]
        let t = clamped - Double(lower)

        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        let fromTs = from.timestamp.timeIntervalSince1970
        let toTs = to.timestamp.timeIntervalSince1970

        return TrackPoint(
            latitude: lerp(from.latitude, to.latitude),
            longitude: lerp(from.longitude, to.longitude),
            altitude: lerp(from.altitude, to.altitude),
            horizontalAccuracy: lerp(from.horizontalAccuracy, to.horizontalAccuracy),
            verticalAccuracy: lerp(from.verticalAccuracy, to.verticalAccuracy),
            speed: from.speed >= 0 ? lerp(from.speed, to.speed) : -1,
            course: from.course >= 0 ? lerp(from.course, to.course) : -1,
            timestamp: Date(timeIntervalSince1970: lerp(fromTs, toTs))
        )
    }
}

struct RunMetricCard: View {
    let icon: String
    let title: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(row.1)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Run Stat Card

struct RunStatCard: View {
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
                    .font(.title3)
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

// MARK: - Preview

#Preview {
    HistoryView()
        .environmentObject(SessionStore())
}
