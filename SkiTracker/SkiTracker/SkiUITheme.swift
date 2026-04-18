import SwiftUI

// MARK: - Ski UI Theme

enum SkiPalette {
    static let backgroundTop = Color(red: 0.04, green: 0.09, blue: 0.15)
    static let backgroundBottom = Color(red: 0.02, green: 0.05, blue: 0.09)
    static let cardTop = Color(red: 0.08, green: 0.13, blue: 0.18).opacity(0.94)
    static let cardBottom = Color(red: 0.03, green: 0.07, blue: 0.11).opacity(0.90)
    static let stroke = Color.white.opacity(0.14)
    static let shadow = Color.black.opacity(0.42)

    static let primary = Color(red: 0.16, green: 0.63, blue: 1.00)
    static let cyan = Color(red: 0.39, green: 0.90, blue: 1.00)
    static let green = Color(red: 0.36, green: 0.85, blue: 0.58)
    static let yellow = Color(red: 1.00, green: 0.80, blue: 0.18)
    static let orange = Color(red: 1.00, green: 0.58, blue: 0.18)
    static let red = Color(red: 1.00, green: 0.30, blue: 0.36)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.70)
    static let textTertiary = Color.white.opacity(0.46)
}

struct SkiScreenBackground<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [SkiPalette.backgroundTop, SkiPalette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [SkiPalette.primary.opacity(0.24), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 340
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [SkiPalette.green.opacity(0.14), .clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 280
            )
            .ignoresSafeArea()

            content
        }
    }
}

struct SkiGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 26
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .background(
            LinearGradient(
                colors: [SkiPalette.cardTop, SkiPalette.cardBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(SkiPalette.stroke, lineWidth: 1)
        )
        .shadow(color: SkiPalette.shadow, radius: 18, y: 10)
    }
}

struct SkiIconBadge: View {
    let systemName: String
    var tint: Color = SkiPalette.primary
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .stroke(SkiPalette.stroke, lineWidth: 1)
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

struct SkiStatusPill: View {
    let title: String
    let systemName: String
    var tint: Color = SkiPalette.primary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .foregroundStyle(tint)
            Text(title)
                .foregroundStyle(SkiPalette.textPrimary)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.22), in: Capsule())
        .overlay(
            Capsule()
                .stroke(SkiPalette.stroke, lineWidth: 1)
        )
    }
}

struct SkiActionButton: View {
    let title: String
    let subtitle: String?
    let systemName: String
    let colors: [Color]
    var secondarySystemName: String? = nil
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Image(systemName: systemName)
                .font(.system(size: compact ? 14 : 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
                .background(.white.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: compact ? 14 : 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                if !compact, let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            Spacer(minLength: 0)

            if let secondarySystemName, !compact {
                Image(systemName: secondarySystemName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.14), in: Circle())
            }
        }
        .padding(.horizontal, compact ? 12 : 18)
        .padding(.vertical, compact ? 13 : 18)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: compact ? 18 : 24, style: .continuous)
        )
        .shadow(color: colors.first?.opacity(0.30) ?? .clear, radius: compact ? 10 : 16, y: compact ? 6 : 10)
    }
}

struct SkiPrimaryButtonLabel: View {
    let title: String
    var systemName: String? = nil
    var colors: [Color] = [SkiPalette.primary, SkiPalette.cyan]
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .bold))
            }

            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: colors.first?.opacity(0.24) ?? .clear, radius: 14, y: 8)
    }
}

struct SkiSecondaryButtonLabel: View {
    let title: String
    var systemName: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemName {
                Image(systemName: systemName)
            }
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(SkiPalette.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SkiPalette.stroke, lineWidth: 1)
        )
    }
}

struct SkiSectionTitle: View {
    let eyebrow: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(0.9)
                .foregroundStyle(SkiPalette.textTertiary)
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(SkiPalette.textPrimary)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(SkiPalette.textSecondary)
            }
        }
    }
}
