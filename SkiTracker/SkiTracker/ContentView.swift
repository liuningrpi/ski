import SwiftUI
import CoreLocation

// MARK: - ContentView

/// Main screen of the Ski Tracker app.
/// Handles permission flow, start/stop tracking, live map, and statistics.
struct ContentView: View {

    @EnvironmentObject var tracker: LocationTracker
    @EnvironmentObject var sessionStore: SessionStore

    @State private var showHistory = false
    @State private var showStopConfirm = false
    @State private var liveSession: TrackSession?

    /// Timer to refresh stats every second
    @State private var statsTimer: Timer?

    /// Trigger for stats refresh
    @State private var statsTick: Int = 0

    var body: some View {
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
            .navigationTitle("Ski Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    authStatusBadge
                }
            }
            .sheet(isPresented: $showHistory) {
                HistoryView()
            }
            .alert("停止录制？", isPresented: $showStopConfirm) {
                Button("继续录制", role: .cancel) { }
                Button("停止并保存", role: .destructive) {
                    stopAndSave()
                }
            } message: {
                Text("当前轨迹将被保存，你可以在历史记录中回看。")
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
        let _ = statsTick // force refresh
        let session = buildLiveSession()

        VStack(spacing: 8) {
            // Compact live indicator
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("录制中")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                Spacer()
                Text("\(tracker.locations.count) 点")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 12)

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

    // MARK: - Control Bar

    @ViewBuilder
    private var controlBar: some View {
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
                        Text("停止录制")
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
                        Text("开始滑雪")
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
        VStack(spacing: 8) {
            Text("需要定位权限才能记录滑雪轨迹")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if tracker.authorizationStatus == .denied {
                Button("前往设置开启定位") {
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
                        Text("授权定位")
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

    // MARK: - Auth Status Badge

    @ViewBuilder
    private var authStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tracker.canTrack ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(tracker.authStatusDescription)
                .font(.caption2)
                .foregroundColor(.secondary)
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
