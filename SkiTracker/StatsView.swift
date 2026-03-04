import SwiftUI

// MARK: - StatsView

/// Displays skiing statistics in a compact grid layout.
struct StatsView: View {

    let durationFormatted: String
    let distanceKm: Double
    let maxSpeedKmh: Double
    let avgSpeedKmh: Double
    let maxAltitude: Double
    let elevationDrop: Double
    let pointCount: Int

    var body: some View {
        VStack(spacing: 12) {
            // Row 1: Duration & Distance
            HStack(spacing: 16) {
                StatCard(
                    icon: "timer",
                    title: "时长",
                    value: durationFormatted,
                    unit: ""
                )
                StatCard(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    title: "距离",
                    value: String(format: "%.2f", distanceKm),
                    unit: "km"
                )
            }

            // Row 2: Max Speed & Avg Speed
            HStack(spacing: 16) {
                StatCard(
                    icon: "gauge.with.needle.fill",
                    title: "最高速度",
                    value: String(format: "%.1f", maxSpeedKmh),
                    unit: "km/h"
                )
                StatCard(
                    icon: "speedometer",
                    title: "平均速度",
                    value: String(format: "%.1f", avgSpeedKmh),
                    unit: "km/h"
                )
            }

            // Row 3: Max Altitude & Elevation Drop
            HStack(spacing: 16) {
                StatCard(
                    icon: "mountain.2.fill",
                    title: "最高海拔",
                    value: String(format: "%.0f", maxAltitude),
                    unit: "m"
                )
                StatCard(
                    icon: "arrow.down.right",
                    title: "海拔落差",
                    value: String(format: "%.0f", elevationDrop),
                    unit: "m"
                )
            }

            // Point count (subtle)
            Text("轨迹点数: \(pointCount)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
}

// MARK: - StatCard

/// A single statistic card with icon, title, value, and unit.
struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Preview

#Preview {
    StatsView(
        durationFormatted: "12:34",
        distanceKm: 3.45,
        maxSpeedKmh: 67.2,
        avgSpeedKmh: 32.1,
        maxAltitude: 2450,
        elevationDrop: 680,
        pointCount: 1234
    )
}
