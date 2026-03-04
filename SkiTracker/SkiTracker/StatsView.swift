import SwiftUI

// MARK: - StatsView

/// Displays skiing statistics in a compact grid layout.
struct StatsView: View {

    @ObservedObject var settings = SettingsManager.shared

    let durationFormatted: String
    let distanceKm: Double
    let maxSpeedKmh: Double
    let avgSpeedKmh: Double
    let maxAltitude: Double
    let elevationDrop: Double
    let pointCount: Int

    var body: some View {
        let strings = settings.strings
        let units = settings.unitSystem

        VStack(spacing: 12) {
            // Row 1: Duration & Distance
            HStack(spacing: 16) {
                StatCard(
                    icon: "timer",
                    title: strings.duration,
                    value: durationFormatted,
                    unit: ""
                )
                StatCard(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    title: strings.distance,
                    value: settings.formatDistance(distanceKm),
                    unit: units.distanceUnit
                )
            }

            // Row 2: Max Speed & Avg Speed
            HStack(spacing: 16) {
                StatCard(
                    icon: "gauge.with.needle.fill",
                    title: strings.maxSpeed,
                    value: settings.formatSpeed(maxSpeedKmh),
                    unit: units.speedUnit
                )
                StatCard(
                    icon: "speedometer",
                    title: strings.avgSpeed,
                    value: settings.formatSpeed(avgSpeedKmh),
                    unit: units.speedUnit
                )
            }

            // Row 3: Max Altitude & Elevation Drop
            HStack(spacing: 16) {
                StatCard(
                    icon: "mountain.2.fill",
                    title: strings.maxAltitude,
                    value: settings.formatAltitude(maxAltitude),
                    unit: units.altitudeUnit
                )
                StatCard(
                    icon: "arrow.down.right",
                    title: strings.elevationDrop,
                    value: settings.formatAltitude(elevationDrop),
                    unit: units.altitudeUnit
                )
            }

            // Point count (subtle)
            Text("\(strings.trackPoints): \(pointCount)")
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
