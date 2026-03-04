import SwiftUI
import CoreLocation

// MARK: - HistoryView

/// Displays all saved sessions with ability to view details.
struct HistoryView: View {

    @EnvironmentObject var sessionStore: SessionStore
    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSession: TrackSession?
    @State private var showDeleteAllConfirm = false

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            Group {
                if sessionStore.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
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
        }
    }

    // MARK: - Session List

    @ViewBuilder
    private var sessionList: some View {
        let strings = settings.strings
        let units = settings.unitSystem

        List {
            ForEach(sessionStore.sessions) { session in
                Button {
                    selectedSession = session
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.startedAt, style: .date)
                                .font(.headline)
                                .foregroundColor(.primary)
                            HStack {
                                Text(session.startedAt, style: .time)
                                if let end = session.endedAt {
                                    Text("-")
                                    Text(end, style: .time)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(settings.formatDistance(session.totalDistanceKm)) \(units.distanceUnit)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text(session.durationFormatted)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: deleteSession)
        }
        .listStyle(.insetGrouped)
    }

    private func deleteSession(at offsets: IndexSet) {
        for index in offsets {
            let session = sessionStore.sessions[index]
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

// MARK: - Session Detail View

struct SessionDetailView: View {

    let session: TrackSession

    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Session info header
                    sessionHeader

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
                    .padding(.bottom, 20)
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
