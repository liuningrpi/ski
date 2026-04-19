import SwiftUI
import CoreLocation

// MARK: - ContentView

/// Main screen of the Ski Tracker app.
/// Handles permission flow, start/stop tracking, live map, and statistics.
struct ContentView: View {

    @EnvironmentObject var tracker: LocationTracker
    @EnvironmentObject var sessionStore: SessionStore
    @ObservedObject var settings = SettingsManager.shared

    @State private var showHistory = false
    @State private var showLeaderboard = false
    @State private var showFriends = false
    @State private var showSettings = false
    @State private var showStopConfirm = false
    @ObservedObject private var watchHeartRateReceiver = WatchHeartRateReceiver.shared

    /// Timer to refresh stats every second.
    @State private var statsTimer: Timer?

    /// Trigger for stats refresh.
    @State private var statsTick: Int = 0
    @State private var liveHeartRateStats = HeartRateStats(maxBPM: nil, avgBPM: nil)
    @State private var isPollingHeartRate = false
    @State private var activeLiveSessionId: String?
    @State private var isLivePanelCollapsed = false
    @State private var isLiveMapAutoFollow = true
    @State private var liveMapRecenterTrigger = 0

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            ZStack(alignment: .bottom) {
                mapLayer
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.56),
                        Color.clear,
                        Color.black.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    topChrome

                    if tracker.isTracking, let message = tracker.resortWelcomeMessage {
                        welcomeBanner(message)
                            .padding(.top, 14)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .animation(.easeInOut(duration: 0.24), value: message)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                if tracker.isTracking && !isLiveMapAutoFollow {
                    recenterButton
                        .padding(.trailing, 16)
                        .padding(.bottom, tracker.isTracking ? 370 : 210)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                bottomOverlay
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showHistory) {
                HistoryView()
            }
            .sheet(isPresented: $showLeaderboard) {
                LeaderboardView()
                    .environmentObject(sessionStore)
            }
            .sheet(isPresented: $showFriends) {
                FriendsView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert(strings.stopConfirmTitle, isPresented: $showStopConfirm) {
                Button(strings.continueRecording, role: .cancel) { }
                Button(strings.stopAndSave, role: .destructive) {
                    stopAndSave()
                }
            } message: {
                Text(strings.stopConfirmMessage)
            }
            .onAppear {
                tracker.segmenter.onSegmentCompleted = nil
            }
            .onDisappear {
                statsTimer?.invalidate()
                HeartRateService.shared.stopLiveUpdates()
                watchHeartRateReceiver.endLiveSession()
                tracker.segmenter.onSegmentCompleted = nil
            }
            .onReceive(watchHeartRateReceiver.$liveStats) { stats in
                guard tracker.isTracking else { return }
                guard stats.maxBPM != nil || stats.avgBPM != nil else { return }
                liveHeartRateStats = stats
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top Chrome

    private var topChrome: some View {
        HStack(spacing: 10) {
            // Left-most
            floatingIconButton(systemName: "person.2.fill", tint: SkiPalette.green) {
                showFriends = true
            }

            // Second from left
            floatingIconButton(systemName: "trophy.fill", tint: SkiPalette.yellow) {
                showLeaderboard = true
            }

            Spacer()

            // Second from right
            floatingIconButton(systemName: "clock.arrow.circlepath", tint: SkiPalette.primary) {
                showHistory = true
            }

            // Right-most
            floatingIconButton(systemName: "gearshape.fill", tint: SkiPalette.textPrimary) {
                showSettings = true
            }
        }
    }

    private func floatingIconButton(systemName: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.24))
                Circle()
                    .stroke(SkiPalette.stroke, lineWidth: 1)
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 50, height: 50)
        }
    }

    private func welcomeBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "mountain.2.fill")
                .foregroundStyle(SkiPalette.green)
            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(SkiPalette.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.black.opacity(0.34), in: Capsule())
        .overlay(
            Capsule()
                .stroke(SkiPalette.stroke, lineWidth: 1)
        )
    }

    private var recenterButton: some View {
        Button {
            isLiveMapAutoFollow = true
            liveMapRecenterTrigger += 1
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(
                    LinearGradient(
                        colors: [SkiPalette.primary, SkiPalette.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .stroke(SkiPalette.stroke, lineWidth: 1)
                )
                .shadow(color: SkiPalette.primary.opacity(0.35), radius: 16, y: 10)
        }
    }

    // MARK: - Map Layer

    @ViewBuilder
    private var mapLayer: some View {
        let coords = tracker.locations.map { $0.coordinate }
        if coords.isEmpty {
            TrackMapView(
                coordinates: [],
                followUser: false,
                fitToRouteWhenNotFollowing: false,
                showEndMarker: false,
                recenterTrigger: liveMapRecenterTrigger
            )
        } else {
            TrackMapView(
                coordinates: coords,
                followUser: tracker.isTracking ? isLiveMapAutoFollow : true,
                fitToRouteWhenNotFollowing: !tracker.isTracking,
                showEndMarker: true,
                recenterTrigger: liveMapRecenterTrigger
            ) {
                if tracker.isTracking && isLiveMapAutoFollow {
                    isLiveMapAutoFollow = false
                }
            }
        }
    }

    // MARK: - Bottom Overlay

    private var bottomOverlay: some View {
        VStack(spacing: 12) {
            if tracker.isTracking {
                liveStatsPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            controlBar
        }
        .frame(maxWidth: 760)
    }

    // MARK: - Live Stats Panel

    @ViewBuilder
    private var liveStatsPanel: some View {
        let strings = settings.strings
        let units = settings.unitSystem
        let _ = statsTick
        let session = buildLiveSession()
        let segmenter = tracker.segmenter

        SkiGlassCard(cornerRadius: 28, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(tracker.isPaused ? SkiPalette.yellow : SkiPalette.red)
                                .frame(width: 8, height: 8)
                            Text(tracker.isPaused ? strings.paused.uppercased() : strings.recording.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .kerning(0.8)
                                .foregroundStyle(tracker.isPaused ? SkiPalette.yellow : SkiPalette.red)
                        }

                        Text(stateName(segmenter.currentState))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(SkiPalette.textPrimary)

                        Text(summaryDescription(for: segmenter.currentState))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(SkiPalette.textSecondary)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 10) {
                        SkiStatusPill(
                            title: stateName(segmenter.currentState),
                            systemName: stateIcon(segmenter.currentState),
                            tint: stateColor(segmenter.currentState)
                        )

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                isLivePanelCollapsed.toggle()
                            }
                        } label: {
                            Image(systemName: isLivePanelCollapsed ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(SkiPalette.textPrimary)
                                .frame(width: 34, height: 34)
                                .background(.black.opacity(0.25), in: Circle())
                                .overlay(
                                    Circle()
                                        .stroke(SkiPalette.stroke, lineWidth: 1)
                                )
                        }
                    }
                }

                HStack(spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            liveSummaryChips(strings: strings, units: units, segmenter: segmenter)
                        }
                        VStack(spacing: 10) {
                            liveSummaryChips(strings: strings, units: units, segmenter: segmenter)
                        }
                    }
                }

                if !isLivePanelCollapsed {
                        StatsView(
                            durationFormatted: session.durationFormatted,
                            distanceKm: session.totalDistanceKm,
                            maxSpeedKmh: session.maxSpeedKmh,
                            avgSpeedKmh: session.avgSpeedKmh,
                            maxAltitude: session.maxAltitude,
                            elevationDrop: session.elevationDrop,
                            pointCount: session.points.count,
                            showHeartRate: true,
                            maxHeartRateBPM: liveHeartRateStats.maxBPM,
                            avgHeartRateBPM: liveHeartRateStats.avgBPM,
                            compact: true
                        )

                    if statsTick >= 20 && liveHeartRateStats.maxBPM == nil {
                        Text(strings.waitingHeartRateData)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(SkiPalette.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func liveSummaryChip(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SkiPalette.textSecondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(SkiPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SkiPalette.stroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func liveSummaryChips(strings: LocalizedStrings, units: UnitSystem, segmenter: RunSegmenter) -> some View {
        liveSummaryChip(
            icon: "figure.skiing.downhill",
            label: strings.runsCount,
            value: "\(segmenter.skiingRunCount)",
            tint: SkiPalette.primary
        )
        liveSummaryChip(
            icon: "cablecar",
            label: strings.stateLift,
            value: "\(segmenter.liftCount)",
            tint: SkiPalette.yellow
        )
        liveSummaryChip(
            icon: "arrow.down.right",
            label: strings.elevationDrop,
            value: "\(settings.formatAltitude(segmenter.totalVerticalDrop)) \(units.altitudeUnit)",
            tint: SkiPalette.green
        )
    }

    private func summaryDescription(for state: SkiingState) -> String {
        let strings = settings.strings
        switch state {
        case .idle:
            return strings.stateIdle
        case .skiing:
            return strings.maxSpeed
        case .lift:
            return strings.stateLift
        case .stopped:
            return strings.stateStopped
        }
    }

    // MARK: - State Helpers

    private func stateIcon(_ state: SkiingState) -> String {
        switch state {
        case .idle: return "pause.circle"
        case .skiing: return "figure.skiing.downhill"
        case .lift: return "cablecar"
        case .stopped: return "stop.circle"
        }
    }

    private func stateColor(_ state: SkiingState) -> Color {
        switch state {
        case .idle: return SkiPalette.textSecondary
        case .skiing: return SkiPalette.primary
        case .lift: return SkiPalette.yellow
        case .stopped: return SkiPalette.red
        }
    }

    private func stateName(_ state: SkiingState) -> String {
        let strings = settings.strings
        switch state {
        case .idle: return strings.stateIdle
        case .skiing: return strings.stateSkiing
        case .lift: return strings.stateLift
        case .stopped: return strings.stateStopped
        }
    }

    // MARK: - Control Bar

    @ViewBuilder
    private var controlBar: some View {
        let strings = settings.strings

        if tracker.isTracking {
            SkiGlassCard(cornerRadius: 28, padding: 12) {
                HStack(spacing: 10) {
                    recordingControlButtons(strings: strings)
                }
            }
        } else {
            Button {
                startTracking()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "figure.skiing.downhill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.14), in: Circle())

                    Text(strings.startSkiing)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Image(systemName: "figure.snowboarding")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [SkiPalette.primary, SkiPalette.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .shadow(color: SkiPalette.primary.opacity(0.30), radius: 16, y: 10)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func recordingControlButtons(strings: LocalizedStrings) -> some View {
        Button {
            if tracker.isPaused {
                resumeTracking()
            } else {
                pauseTracking()
            }
        } label: {
            SkiActionButton(
                title: tracker.isPaused ? strings.resumeRecording : strings.pauseRecording,
                subtitle: tracker.isPaused ? strings.recording : strings.paused,
                systemName: tracker.isPaused ? "play.fill" : "pause.fill",
                colors: tracker.isPaused
                    ? [SkiPalette.primary, SkiPalette.cyan]
                    : [SkiPalette.orange, SkiPalette.yellow],
                compact: true
            )
        }
        .buttonStyle(.plain)

        Button {
            showStopConfirm = true
        } label: {
            SkiActionButton(
                title: strings.stopRecording,
                subtitle: strings.stopAndSave,
                systemName: "stop.fill",
                colors: [SkiPalette.red, Color(red: 0.85, green: 0.18, blue: 0.28)],
                compact: true
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Permission Section

    private var permissionSection: some View {
        let strings = settings.strings

        return SkiGlassCard(cornerRadius: 32, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                SkiSectionTitle(
                    eyebrow: strings.appTitle,
                    title: strings.locationPermissionNeeded,
                    detail: tracker.authorizationStatus == .denied ? strings.goToSettings : strings.authorizeLocation
                )

                if tracker.authorizationStatus == .denied {
                    Button(strings.goToSettings) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            colors: [SkiPalette.orange, SkiPalette.yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                } else {
                    Button {
                        tracker.requestPermission()
                    } label: {
                        SkiActionButton(
                            title: strings.authorizeLocation,
                            subtitle: strings.startSkiing,
                            systemName: "location.fill",
                            colors: [SkiPalette.primary, SkiPalette.cyan]
                        )
                    }
                }

                if let error = tracker.errorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SkiPalette.red)
                }
            }
        }
    }

    // MARK: - Actions

    private func startTracking() {
        tracker.startTracking()
        guard tracker.isTracking else { return }

        let liveSessionId = UUID().uuidString
        activeLiveSessionId = liveSessionId
        isLivePanelCollapsed = false
        isLiveMapAutoFollow = true
        liveMapRecenterTrigger += 1

        liveHeartRateStats = HeartRateStats(maxBPM: nil, avgBPM: nil)
        isPollingHeartRate = false
        statsTick = 0
        startStatsTimer()

        startLiveHeartRateUpdates()
        if let start = tracker.trackingStartDate {
            watchHeartRateReceiver.beginLiveSession(sessionId: liveSessionId, startedAt: start)
        }
    }

    private func pauseTracking() {
        guard tracker.isTracking, !tracker.isPaused else { return }
        tracker.pauseTracking()
        statsTimer?.invalidate()
        statsTimer = nil
        HeartRateService.shared.stopLiveUpdates()
        watchHeartRateReceiver.endLiveSession()
        isPollingHeartRate = false
    }

    private func resumeTracking() {
        guard tracker.isTracking, tracker.isPaused else { return }
        tracker.resumeTracking()
        startStatsTimer()
        startLiveHeartRateUpdates()

        if activeLiveSessionId == nil {
            activeLiveSessionId = UUID().uuidString
        }
        if let sessionId = activeLiveSessionId {
            watchHeartRateReceiver.beginLiveSession(sessionId: sessionId, startedAt: Date())
        }
    }

    private func stopAndSave() {
        statsTimer?.invalidate()
        statsTimer = nil
        tracker.stopTracking()
        persistFullSession()

        HeartRateService.shared.stopLiveUpdates()
        watchHeartRateReceiver.endLiveSession()
        liveHeartRateStats = HeartRateStats(maxBPM: nil, avgBPM: nil)
        isPollingHeartRate = false
        activeLiveSessionId = nil
        isLiveMapAutoFollow = true
        statsTick = 0
    }

    private func startStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            statsTick += 1
            if statsTick % 10 == 0 {
                pollLiveHeartRate()
            }
        }
    }

    private func buildLiveSession() -> TrackSession {
        var session = TrackSession(
            startedAt: tracker.trackingStartDate ?? Date(),
            deviceInfo: nil
        )
        session.points = tracker.locations.map { TrackPoint(from: $0) }
        return session
    }

    private func persistFullSession() {
        let session = tracker.buildSession()
        guard session.points.count >= 2 else { return }
        sessionStore.save(session)

        if let user = AuthService.shared.currentUser {
            Task {
                do {
                    try await FirestoreService.shared.uploadSession(session, uid: user.uid)
                } catch {
                    await MainActor.run {
                        FirestoreService.shared.errorMessage = error.localizedDescription
                    }
                }
            }
        }

        refreshLeaderboard(newSessions: [session])
    }

    private func refreshLeaderboard(newSessions: [TrackSession]) {
        guard !newSessions.isEmpty else { return }
        let newIDs = Set(newSessions.map(\.id))
        let existing = sessionStore.sessions.filter { !newIDs.contains($0.id) }
        let latestSessions = newSessions + existing
        if let user = AuthService.shared.currentUser {
            Task {
                await LeaderboardService.shared.refreshLeaderboard(
                    for: user,
                    localSessions: latestSessions,
                    showLoading: false
                )
            }
        } else {
            LeaderboardService.shared.useLocalOnly(user: nil, sessions: latestSessions)
        }
    }

    private func startLiveHeartRateUpdates() {
        guard tracker.isTracking, let start = tracker.trackingStartDate else {
            liveHeartRateStats = HeartRateStats(maxBPM: nil, avgBPM: nil)
            return
        }

        HeartRateService.shared.startLiveUpdates(start: start) { stats in
            if tracker.isTracking {
                liveHeartRateStats = stats
            }
        }
    }

    private func pollLiveHeartRate() {
        guard tracker.isTracking,
              let start = tracker.trackingStartDate,
              !isPollingHeartRate else {
            return
        }

        if watchHeartRateReceiver.hasRecentSample {
            return
        }

        isPollingHeartRate = true
        let end = Date()

        Task {
            let polled = await HeartRateService.shared.fetchStats(start: start, end: end)
            await MainActor.run {
                if tracker.isTracking {
                    let maxBPM = max(liveHeartRateStats.maxBPM ?? 0, polled.maxBPM ?? 0)
                    let avgCandidates = [liveHeartRateStats.avgBPM, polled.avgBPM].compactMap { $0 }
                    let avgBPM = avgCandidates.isEmpty ? nil : (avgCandidates.reduce(0, +) / Double(avgCandidates.count))
                    if maxBPM > 0 || avgBPM != nil {
                        liveHeartRateStats = HeartRateStats(
                            maxBPM: maxBPM > 0 ? maxBPM : nil,
                            avgBPM: avgBPM
                        )
                    }
                }
                isPollingHeartRate = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(LocationTracker())
        .environmentObject(SessionStore())
}
