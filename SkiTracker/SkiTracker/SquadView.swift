import SwiftUI
import MapKit

struct SquadView: View {

    @ObservedObject private var squadService = SquadService.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var settings = SettingsManager.shared
    @EnvironmentObject var tracker: LocationTracker
    @Environment(\.dismiss) private var dismiss

    @State private var createName = ""
    @State private var createResort = ""
    @State private var joinCode = ""
    @State private var shareOnlyWhenRecording = true
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            List {
                if authService.currentUser == nil {
                    Section {
                        Text("Please sign in to use Squad.")
                            .foregroundColor(.secondary)
                    }
                } else if let session = squadService.currentSession {
                    activeSessionSection(session: session)
                    mapSection
                    memberSection
                    controlsSection
                } else {
                    createSection
                    joinSection
                }

                if let pending = squadService.pendingSelfCheck {
                    selfCheckSection(alert: pending)
                }

                if let status = squadService.statusMessage, !status.isEmpty {
                    Section {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                if let error = squadService.errorMessage, !error.isEmpty {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Squad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(settings.strings.close) { dismiss() }
                }
            }
            .task(id: authService.currentUser?.uid ?? "guest") {
                await squadService.bootstrapIfNeeded()
            }
            .onReceive(squadService.$members) { _ in
                refreshMapCameraIfNeeded()
            }
            .onAppear {
                refreshMapCameraIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var createSection: some View {
        Section("Create Squad") {
            TextField("Squad name (optional)", text: $createName)
            TextField("Resort (optional)", text: $createResort)

            Toggle("Only share while recording", isOn: $shareOnlyWhenRecording)

            Button {
                Task {
                    await squadService.createSquad(
                        name: createName,
                        resort: createResort,
                        shareOnlyWhenRecording: shareOnlyWhenRecording
                    )
                }
            } label: {
                if squadService.isLoading {
                    ProgressView()
                } else {
                    Label("Create", systemImage: "person.3.fill")
                }
            }
        }
    }

    @ViewBuilder
    private var joinSection: some View {
        Section("Join Squad") {
            TextField("6-digit invite code", text: $joinCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            Button {
                Task { await squadService.joinSquad(code: joinCode) }
            } label: {
                Label("Join", systemImage: "person.crop.circle.badge.plus")
            }
        }
    }

    @ViewBuilder
    private func activeSessionSection(session: SquadSessionInfo) -> some View {
        Section("Session") {
            HStack {
                Text("Code")
                Spacer()
                Text(session.code)
                    .fontWeight(.bold)
                    .textSelection(.enabled)
            }

            HStack {
                Text("Name")
                Spacer()
                Text(session.name)
                    .foregroundColor(.secondary)
            }

            if let resort = session.resort, !resort.isEmpty {
                HStack {
                    Text("Resort")
                    Spacer()
                    Text(resort)
                        .foregroundColor(.secondary)
                }
            }

            statusPillRow
        }
    }

    @ViewBuilder
    private var mapSection: some View {
        Section("Live Map") {
            Map(position: $cameraPosition) {
                ForEach(squadService.members) { member in
                    if let coordinate = member.coordinate {
                        Annotation(member.displayName, coordinate: coordinate) {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(markerColor(for: member))
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                Text(member.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                refreshMapCameraIfNeeded(force: true)
            } label: {
                Label("Recenter", systemImage: "location.fill")
            }
        }
    }

    @ViewBuilder
    private var memberSection: some View {
        Section("Members") {
            if squadService.members.isEmpty {
                Text("No members yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(squadService.members) { member in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(member.displayName)
                                .fontWeight(.semibold)
                            if member.role == .captain {
                                Text("Captain")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Text(member.isOnline ? "Online" : "Offline")
                                .font(.caption)
                                .foregroundColor(member.isOnline ? .green : .secondary)
                        }

                        HStack(spacing: 12) {
                            Text("Sharing: \(member.isSharing && !member.pausedSharing ? "ON" : "OFF")")
                            Text("Recording: \(member.isTracking ? "ON" : "OFF")")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        if let last = member.lastUpdated {
                            Text("Last update: \(RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date()))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if member.uid != authService.currentUser?.uid {
                            Button {
                                squadService.sendPing(to: member)
                            } label: {
                                Label("Ping", systemImage: "bell.fill")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var controlsSection: some View {
        Section("Controls") {
            Toggle("Pause sharing", isOn: Binding(
                get: { squadService.isSharingPaused },
                set: { squadService.setSharingPaused($0) }
            ))

            if squadService.amCaptain {
                Button(role: .destructive) {
                    Task { await squadService.endSquadSession() }
                } label: {
                    Label("End Squad Session", systemImage: "stop.circle.fill")
                }
            } else {
                Button(role: .destructive) {
                    Task { await squadService.leaveSquad() }
                } label: {
                    Label("Leave Squad", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    @ViewBuilder
    private func selfCheckSection(alert: SquadAlert) -> some View {
        Section("Safety Check") {
            Text(alert.message)
                .font(.subheadline)
            HStack {
                Button("I'm OK") {
                    squadService.respondSelfCheck(isOK: true)
                }
                .buttonStyle(.borderedProminent)

                Button("Need Help") {
                    squadService.respondSelfCheck(isOK: false)
                }
                .buttonStyle(.bordered)

                Button("Pause 10m") {
                    squadService.pauseAlerts(minutes: 10)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var statusPillRow: some View {
        HStack(spacing: 8) {
            statePill(title: "Sharing", value: squadService.isSharingPaused ? "OFF" : "ON", color: squadService.isSharingPaused ? .orange : .green)
            statePill(title: "Recording", value: tracker.isTracking ? "ON" : "OFF", color: tracker.isTracking ? .blue : .gray)
            statePill(title: "GPS", value: gpsStateText, color: gpsStateColor)
        }
        .font(.caption2)
    }

    private func statePill(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Text(value)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .clipShape(Capsule())
    }

    private var gpsStateText: String {
        guard let accuracy = tracker.currentLocation?.horizontalAccuracy, accuracy > 0 else { return "Weak" }
        return accuracy <= 25 ? "Good" : "Weak"
    }

    private var gpsStateColor: Color {
        gpsStateText == "Good" ? .green : .orange
    }

    private func markerColor(for member: SquadMemberPresence) -> Color {
        if member.pausedSharing { return .gray }
        if member.role == .captain { return .blue }
        return member.isOnline ? .green : .orange
    }

    private func refreshMapCameraIfNeeded(force: Bool = false) {
        let coords = squadService.members.compactMap { $0.coordinate }
        guard !coords.isEmpty else { return }
        if !force {
            return
        }

        if coords.count == 1, let first = coords.first {
            cameraPosition = .region(MKCoordinateRegion(
                center: first,
                latitudinalMeters: 1200,
                longitudinalMeters: 1200
            ))
            return
        }

        var rect = MKMapRect.null
        for coord in coords {
            let point = MKMapPoint(coord)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            rect = rect.isNull ? pointRect : rect.union(pointRect)
        }

        cameraPosition = .rect(rect)
    }
}

#Preview {
    SquadView()
        .environmentObject(LocationTracker())
}
