import SwiftUI

// MARK: - StatsView

/// Displays skiing statistics in a premium two-column grid layout.
struct StatsView: View {

    @ObservedObject var settings = SettingsManager.shared

    let durationFormatted: String
    let distanceKm: Double
    let maxSpeedKmh: Double
    let avgSpeedKmh: Double
    let maxAltitude: Double
    let elevationDrop: Double
    let pointCount: Int
    let showHeartRate: Bool
    let maxHeartRateBPM: Double?
    let avgHeartRateBPM: Double?
    var compact: Bool = false

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: compact ? 8 : 12),
            GridItem(.flexible(), spacing: compact ? 8 : 12)
        ]
    }

    var body: some View {
        let strings = settings.strings
        let units = settings.unitSystem

        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            LazyVGrid(columns: columns, spacing: compact ? 8 : 12) {
                StatCard(
                    icon: "timer",
                    title: strings.duration,
                    value: durationFormatted,
                    unit: "",
                    accent: SkiPalette.primary,
                    compact: compact
                )
                StatCard(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    title: strings.distance,
                    value: settings.formatDistance(distanceKm),
                    unit: units.distanceUnit,
                    accent: SkiPalette.cyan,
                    compact: compact
                )
                StatCard(
                    icon: "gauge.with.needle.fill",
                    title: strings.maxSpeed,
                    value: settings.formatSpeed(maxSpeedKmh),
                    unit: units.speedUnit,
                    accent: SkiPalette.yellow,
                    compact: compact
                )
                StatCard(
                    icon: "speedometer",
                    title: strings.avgSpeed,
                    value: settings.formatSpeed(avgSpeedKmh),
                    unit: units.speedUnit,
                    accent: SkiPalette.primary,
                    compact: compact
                )
                StatCard(
                    icon: "mountain.2.fill",
                    title: strings.maxAltitude,
                    value: settings.formatAltitude(maxAltitude),
                    unit: units.altitudeUnit,
                    accent: SkiPalette.green,
                    compact: compact
                )
                StatCard(
                    icon: "arrow.down.right",
                    title: strings.elevationDrop,
                    value: settings.formatAltitude(elevationDrop),
                    unit: units.altitudeUnit,
                    accent: SkiPalette.green,
                    compact: compact
                )

                if showHeartRate {
                    StatCard(
                        icon: "heart.fill",
                        title: strings.maxHeartRate,
                        value: heartRateText(maxHeartRateBPM),
                        unit: strings.heartRateUnit,
                        accent: SkiPalette.red,
                        compact: compact
                    )
                    StatCard(
                        icon: "heart.text.square.fill",
                        title: strings.avgHeartRate,
                        value: heartRateText(avgHeartRateBPM),
                        unit: strings.heartRateUnit,
                        accent: SkiPalette.red,
                        compact: compact
                    )
                }
            }

            Text("\(strings.trackPoints): \(pointCount)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(SkiPalette.textTertiary)
                .padding(.horizontal, 4)
        }
    }

    private func heartRateText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f", value)
    }
}

// MARK: - StatCard

/// A single metric tile styled to match the alpine redesign.
struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    var accent: Color = SkiPalette.primary
    var compact: Bool = false

    var body: some View {
        SkiGlassCard(cornerRadius: compact ? 18 : 24, padding: compact ? 10 : 16) {
            VStack(alignment: .leading, spacing: compact ? 8 : 16) {
                HStack(spacing: compact ? 7 : 10) {
                    SkiIconBadge(systemName: icon, tint: accent, size: compact ? 28 : 38)
                    Text(title)
                        .font(.system(size: compact ? 10 : 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(SkiPalette.textSecondary)
                        .lineLimit(compact ? 1 : 2)
                        .minimumScaleFactor(0.72)
                    Spacer(minLength: 0)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: compact ? 19 : 28, weight: .bold, design: .rounded))
                        .foregroundStyle(SkiPalette.textPrimary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.72)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: compact ? 10 : 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(SkiPalette.textSecondary)
                            .lineLimit(1)
                    }
                }

                Capsule()
                    .fill(accent.opacity(0.95))
                    .frame(width: compact ? 28 : 40, height: compact ? 3 : 4)
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 76 : 118, alignment: .leading)
        }
    }
}

// MARK: - Preview

#Preview {
    SkiScreenBackground {
        ScrollView {
            StatsView(
                durationFormatted: "12:34",
                distanceKm: 3.45,
                maxSpeedKmh: 67.2,
                avgSpeedKmh: 32.1,
                maxAltitude: 2450,
                elevationDrop: 680,
                pointCount: 1234,
                showHeartRate: true,
                maxHeartRateBPM: 172,
                avgHeartRateBPM: 146
            )
            .padding(24)
        }
    }
    .preferredColorScheme(.dark)
}
