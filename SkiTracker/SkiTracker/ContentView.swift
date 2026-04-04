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
    @State private var showSettings = false
    @State private var showStopConfirm = false
    @State private var liveSession: TrackSession?
    @ObservedObject private var watchHeartRateReceiver = WatchHeartRateReceiver.shared

    /// Timer to refresh stats every second
    @State private var statsTimer: Timer?

    /// Trigger for stats refresh
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
                // Map layer (full screen)
                mapLayer
                    .ignoresSafeArea(edges: .top)

                if tracker.isTracking, let message = tracker.resortWelcomeMessage {
                    VStack {
                        Text(message)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.green.opacity(0.9))
                            .clipShape(Capsule())
                            .padding(.top, 8)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: message)
                }

                if tracker.isTracking && !isLiveMapAutoFollow {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                isLiveMapAutoFollow = true
                                liveMapRecenterTrigger += 1
                            } label: {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }
                            .padding(.trailing, 16)
                            .padding(.top, 8)
                        }
                        Spacer()
                    }
                }

                // Bottom control panel
                VStack(spacing: 0) {
                    // Stats panel (shown when tracking or reviewing)
                    if tracker.isTracking {
                        liveStatsPanel
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Control buttons
                    controlBar
                }
                .background(.ultraThinMaterial)
            }
            .navigationTitle(strings.appTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showLeaderboard = true
                        } label: {
                            Image(systemName: "trophy.fill")
                        }
                        Button {
                            showHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                HistoryView()
            }
            .sheet(isPresented: $showLeaderboard) {
                LeaderboardView()
                    .environmentObject(sessionStore)
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
    }

    // MARK: - Map Layer

    @ViewBuilder
    private var mapLayer: some View {
        let coords = tracker.locations.map { $0.coordinate }
        if coords.isEmpty {
            // Show default map centered on user or a default location
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

    // MARK: - Live Stats Panel

    @ViewBuilder
    private var liveStatsPanel: some View {
        let strings = settings.strings
        let units = settings.unitSystem
        let _ = statsTick // force refresh
        let session = buildLiveSession()
        let segmenter = tracker.segmenter

        VStack(spacing: 8) {
            // Status bar with state indicator
            HStack {
                // Recording indicator
                Circle()
                    .fill(tracker.isPaused ? Color.yellow : Color.red)
                    .frame(width: 8, height: 8)
                Text(tracker.isPaused ? strings.paused : strings.recording)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(tracker.isPaused ? .yellow : .red)

                Spacer()

                // Current skiing state
                HStack(spacing: 4) {
                    Image(systemName: stateIcon(segmenter.currentState))
                        .foregroundColor(stateColor(segmenter.currentState))
                    Text(stateName(segmenter.currentState))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(stateColor(segmenter.currentState))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(stateColor(segmenter.currentState).opacity(0.15))
                .cornerRadius(8)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isLivePanelCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isLivePanelCollapsed ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            if isLivePanelCollapsed {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.skiing.downhill")
                            .foregroundColor(.blue)
                        Text("\(segmenter.skiingRunCount)")
                            .fontWeight(.bold)
                        Text(strings.runsCount)
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)

                    HStack(spacing: 4) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .foregroundColor(.green)
                        Text("\(settings.formatDistance(session.totalDistanceKm)) \(units.distanceUnit)")
                            .fontWeight(.bold)
                    }
                    .font(.caption)

                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.needle.fill")
                            .foregroundColor(.orange)
                        Text("\(settings.formatSpeed(session.maxSpeedKmh)) \(units.speedUnit)")
                            .fontWeight(.bold)
                    }
                    .font(.caption)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else {
                // Run counter
                HStack(spacing: 16) {
                    // Runs completed
                    HStack(spacing: 4) {
                        Image(systemName: "figure.skiing.downhill")
                            .foregroundColor(.blue)
                        Text("\(segmenter.skiingRunCount)")
                            .fontWeight(.bold)
                        Text(strings.runsCount)
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)

                    // Lifts taken
                    HStack(spacing: 4) {
                        Image(systemName: "cablecar")
                            .foregroundColor(.orange)
                        Text("\(segmenter.liftCount)")
                            .fontWeight(.bold)
                    }
                    .font(.caption)

                    // Vertical drop
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .foregroundColor(.green)
                        Text("\(settings.formatAltitude(segmenter.totalVerticalDrop))")
                            .fontWeight(.bold)
                        Text(units.altitudeUnit)
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)

                    Spacer()
                }
                .padding(.horizontal)

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
                    avgHeartRateBPM: liveHeartRateStats.avgBPM
                )

                if statsTick >= 20 && liveHeartRateStats.maxBPM == nil {
                    Text(strings.waitingHeartRateData)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
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
        case .idle: return .gray
        case .skiing: return .blue
        case .lift: return .orange
        case .stopped: return .yellow
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

        VStack(spacing: 12) {
            if !tracker.canTrack {
                // Permission needed
                permissionSection
            } else if tracker.isTracking {
                HStack(spacing: 12) {
                    Button {
                        if tracker.isPaused {
                            resumeTracking()
                        } else {
                            pauseTracking()
                        }
                    } label: {
                        HStack {
                            Image(systemName: tracker.isPaused ? "play.fill" : "pause.fill")
                            Text(tracker.isPaused ? strings.resumeRecording : strings.pauseRecording)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(tracker.isPaused ? Color.blue : Color.orange)
                        .cornerRadius(14)
                    }

                    Button {
                        showStopConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text(strings.stopRecording)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(14)
                    }
                }
                .padding(.horizontal)
            } else {
                // Start button
                Button {
                    startTracking()
                } label: {
                    HStack {
                        Image(systemName: "figure.skiing.downhill")
                        Text(strings.startSkiing)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(14)
                }
                .padding(.horizontal)
            }

            // Error message
            if let error = tracker.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Permission Section

    @ViewBuilder
    private var permissionSection: some View {
        let strings = settings.strings

        VStack(spacing: 8) {
            Text(strings.locationPermissionNeeded)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if tracker.authorizationStatus == .denied {
                Button(strings.goToSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .cornerRadius(14)
                .padding(.horizontal)
            } else {
                Button {
                    tracker.requestPermission()
                } label: {
                    HStack {
                        Image(systemName: "location.fill")
                        Text(strings.authorizeLocation)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(14)
                }
                .padding(.horizontal)
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

        // Auto-sync newly recorded session for signed-in users.
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
        let latestSessions = sessionStore.sessions
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

        // Watch live stream is authoritative when active/recent.
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
