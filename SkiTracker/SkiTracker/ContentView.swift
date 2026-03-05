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

    /// Timer to refresh stats every second
    @State private var statsTimer: Timer?

    /// Trigger for stats refresh
    @State private var statsTick: Int = 0

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            ZStack(alignment: .bottom) {
                // Map layer (full screen)
                mapLayer
                    .ignoresSafeArea(edges: .top)

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
            .onDisappear {
                statsTimer?.invalidate()
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
                showEndMarker: false
            )
        } else {
            TrackMapView(
                coordinates: coords,
                followUser: true,
                showEndMarker: true
            )
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
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text(strings.recording)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)

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
            }
            .padding(.horizontal)
            .padding(.top, 12)

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
                pointCount: session.points.count
            )
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
                // Stop button
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
        // Start a timer to refresh stats every second
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            statsTick += 1
        }
    }

    private func stopAndSave() {
        statsTimer?.invalidate()
        statsTimer = nil
        tracker.stopTracking()

        let session = tracker.buildSession()
        sessionStore.save(session)

        if let user = AuthService.shared.currentUser {
            let latestSessions = [session] + sessionStore.sessions
            Task {
                await LeaderboardService.shared.refreshLeaderboard(for: user, localSessions: latestSessions)
            }
        } else {
            let latestSessions = [session] + sessionStore.sessions
            LeaderboardService.shared.useLocalOnly(user: nil, sessions: latestSessions)
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
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(LocationTracker())
        .environmentObject(SessionStore())
}
