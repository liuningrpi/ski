import SwiftUI
import CoreLocation

// MARK: - HistoryView

/// Displays the last saved session: map replay + statistics.
struct HistoryView: View {

    @EnvironmentObject var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let session = sessionStore.lastSession {
                    sessionContent(session)
                } else {
                    emptyState
                }
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                if sessionStore.lastSession != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            sessionStore.deleteSaved()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Session Content

    @ViewBuilder
    private func sessionContent(_ session: TrackSession) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Session info header
                sessionHeader(session)

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

                // Disclaimer
                Text("⚠️ 数据基于设备 GPS 定位估算，仅供参考")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Session Header

    @ViewBuilder
    private func sessionHeader(_ session: TrackSession) -> some View {
        VStack(spacing: 4) {
            Text(session.startedAt, style: .date)
                .font(.headline)
            HStack {
                Text(session.startedAt, style: .time)
                if let end = session.endedAt {
                    Text("→")
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.skiing.downhill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("暂无历史记录")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("完成一次滑雪录制后，数据将自动保存在此处")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
        .environmentObject(SessionStore())
}
