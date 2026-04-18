import SwiftUI
import CoreLocation
import StoreKit
import MessageUI
import PhotosUI

// MARK: - SettingsView

/// Settings screen for language, unit preferences, and account.
struct SettingsView: View {

    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var authService = AuthService.shared
    @EnvironmentObject var tracker: LocationTracker
    @EnvironmentObject var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var showLogin = false
    @StateObject private var tipJarStore = TipJarStore()
    @State private var feedbackText = ""
    @State private var showFeedbackSheet = false
    @State private var feedbackStatus: FeedbackStatus = .idle
    @State private var feedbackImages: [UIImage] = []

    enum FeedbackStatus {
        case idle, sending, sent, failed, dailyLimitExceeded
    }

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            SkiScreenBackground {
                List {
                    // Account Section
                    AccountView()

                    // Sign In button (if not logged in)
                    if !authService.isLoggedIn {
                        Section {
                            Button {
                                showLogin = true
                            } label: {
                                SkiPrimaryButtonLabel(title: strings.signIn, systemName: "person.crop.circle")
                            }
                        }
                        .listRowBackground(Color.clear)
                    }

                    // Language Section (menu style to save vertical space)
                    Section {
                        Menu {
                            ForEach(AppLanguage.allCases, id: \.self) { lang in
                                Button {
                                    settings.language = lang
                                } label: {
                                    if settings.language == lang {
                                        Label(lang.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(lang.displayName)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Language")
                                    .foregroundStyle(SkiPalette.textPrimary)
                                Spacer()
                                Text(settings.language.displayName)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(SkiPalette.textSecondary)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(SkiPalette.textSecondary)
                            }
                        }
                    } header: {
                        Label("Language", systemImage: "globe")
                    }
                    .listRowBackground(Color.clear)

                    // Units Section
                    Section {
                        ForEach(UnitSystem.allCases, id: \.self) { unit in
                            Button {
                                settings.unitSystem = unit
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(unitDisplayName(unit))
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(SkiPalette.textPrimary)
                                        Text(unitDescription(unit))
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(SkiPalette.textSecondary)
                                    }
                                    Spacer()
                                    if settings.unitSystem == unit {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(SkiPalette.primary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Label(strings.unitsLabel, systemImage: "ruler")
                    }
                    .listRowBackground(Color.clear)

                    // Location Permission Section
                    Section {
                        HStack {
                            Circle()
                                .fill(tracker.canTrack ? SkiPalette.green : SkiPalette.orange)
                                .frame(width: 10, height: 10)
                            Text(permissionStatusText)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(SkiPalette.textSecondary)
                        }

                        if tracker.authorizationStatus == .notDetermined {
                            Button {
                                tracker.requestPermission()
                            } label: {
                                SkiSecondaryButtonLabel(title: strings.authorizeLocation, systemName: "location.fill")
                            }
                        }

                        if tracker.authorizationStatus == .denied {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                SkiSecondaryButtonLabel(title: strings.goToSettings, systemName: "gearshape")
                            }
                        }

                        if tracker.authorizationStatus == .authorizedWhenInUse {
                            Button {
                                tracker.requestAlwaysPermission()
                            } label: {
                                SkiSecondaryButtonLabel(title: requestAlwaysText, systemName: "arrow.up.circle")
                            }
                        }

                        Text(permissionDetailText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(SkiPalette.textSecondary)
                    } header: {
                        Label(permissionSectionTitle, systemImage: "location.circle")
                    }
                    .listRowBackground(Color.clear)

                    // Performance Sampling Mode
                    Section {
                        Toggle(isOn: $settings.performanceModeEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(strings.performanceModeTitle)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(SkiPalette.textPrimary)
                                Text(strings.performanceModeDescription)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(SkiPalette.textSecondary)
                            }
                        }
                        .tint(SkiPalette.primary)
                    } header: {
                        Label(strings.performanceSection, systemImage: "speedometer")
                    }
                    .listRowBackground(Color.clear)

                    if shouldShowSupportSection {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(strings.supportHeadline)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(SkiPalette.textPrimary)

                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 12) {
                                        supportOptionButtons
                                    }
                                    VStack(spacing: 10) {
                                        supportOptionButtons
                                    }
                                }

                                if !supportStatusText.isEmpty {
                                    Text(supportStatusText)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(SkiPalette.textSecondary)
                                }
                            }
                            .padding(.vertical, 4)
                        } header: {
                            Label(strings.supportTitle, systemImage: "cup.and.saucer.fill")
                        }
                        .listRowBackground(Color.clear)
                    }

                    // Feedback Section
                    Section {
                        Button {
                            showFeedbackSheet = true
                        } label: {
                            HStack(spacing: 12) {
                                SkiIconBadge(systemName: "envelope.fill", tint: SkiPalette.primary, size: 36)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(strings.feedbackButton)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(SkiPalette.textPrimary)
                                    Text(strings.feedbackDescription)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(SkiPalette.textSecondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(SkiPalette.textSecondary)
                            }
                        }
                    } header: {
                        Label(strings.feedbackTitle, systemImage: "text.bubble")
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle(strings.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                await tipJarStore.loadProducts()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(strings.close) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showLogin) {
                LoginView()
            }
            .sheet(isPresented: $showFeedbackSheet) {
                FeedbackSheetView(
                    feedbackText: $feedbackText,
                    feedbackImages: $feedbackImages,
                    feedbackStatus: $feedbackStatus,
                    onSend: sendFeedback
                )
            }
        }
    }

    @ViewBuilder
    private var supportOptionButtons: some View {
        ForEach(tipJarStore.options) { option in
            let isPurchasing = tipJarStore.activePurchaseID == option.id
            Button {
                Task {
                    await tipJarStore.purchase(option: option)
                }
            } label: {
                VStack(spacing: 4) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(buttonTitle(for: option))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(buttonSubtitle(for: option))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .padding(.horizontal, 12)
                .background(
                    LinearGradient(
                        colors: option.id == TipJarStore.smallTipID
                            ? [SkiPalette.orange, SkiPalette.yellow]
                            : [SkiPalette.primary, SkiPalette.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || tipJarStore.isLoading)
        }
    }

    private func sendFeedback() {
        guard !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        feedbackStatus = .sending

        // Get user info
        let userId = authService.currentUser?.uid ?? "anonymous"
        let userEmail = authService.currentUser?.email ?? "N/A"
        let timestamp = ISO8601DateFormatter().string(from: Date())

        Task {
            let result = await LoggingService.shared.logFeedback(
                userId: userId,
                userEmail: userEmail,
                feedback: feedbackText,
                timestamp: timestamp,
                screenshots: feedbackImages
            )

            await MainActor.run {
                switch result {
                case .success:
                    feedbackStatus = .sent
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        showFeedbackSheet = false
                        feedbackText = ""
                        feedbackImages = []
                        feedbackStatus = .idle
                    }
                case .dailyLimitExceeded:
                    feedbackStatus = .dailyLimitExceeded
                case .failure:
                    feedbackStatus = .failed
                }
            }
        }
    }

    private var permissionSectionTitle: String {
        settings.strings.locationPermissionSectionTitle
    }

    private var requestAlwaysText: String {
        settings.strings.requestAlwaysAccess
    }

    private var permissionStatusText: String {
        let strings = settings.strings
        switch tracker.authorizationStatus {
        case .notDetermined: return strings.authNotRequested
        case .restricted: return strings.authRestricted
        case .denied: return strings.authDenied
        case .authorizedWhenInUse: return strings.authWhenInUse
        case .authorizedAlways: return strings.authAlways
        @unknown default: return strings.authUnknown
        }
    }

    private var permissionDetailText: String {
        switch tracker.authorizationStatus {
        case .notDetermined:
            return settings.language == .chinese
                ? "尚未请求定位权限。授权后可开始记录滑雪轨迹。"
                : "Location permission has not been requested yet. Authorize to start tracking."
        case .restricted:
            return settings.language == .chinese
                ? "此设备受系统限制，无法在应用内更改定位权限。"
                : "Location access is restricted by system settings."
        case .denied:
            return settings.language == .chinese
                ? "定位权限已拒绝。请前往系统设置开启。"
                : "Location access is denied. Open system Settings to enable it."
        case .authorizedWhenInUse:
            return settings.language == .chinese
                ? "当前仅在使用应用时允许定位。可申请“始终允许”以支持后台记录。"
                : "Currently allowed only while using app. Request Always access for background tracking."
        case .authorizedAlways:
            return settings.language == .chinese
                ? "已开启“始终允许”，可在后台继续记录。"
                : "Always access enabled. Background tracking is available."
        @unknown default:
            return settings.strings.authUnknown
        }
    }

    private func unitDisplayName(_ unit: UnitSystem) -> String {
        switch settings.language {
        case .chinese, .english, .spanish, .japanese, .korean, .french, .german, .italian:
            return unit == .metric ? settings.strings.metricLabel : settings.strings.imperialLabel
        }
    }

    private func unitDescription(_ unit: UnitSystem) -> String {
        switch unit {
        case .metric:
            return "km/h, km, m"
        case .imperial:
            return "mph, mi, ft"
        }
    }

    private func buttonTitle(for option: TipJarStore.ProductOption) -> String {
        if option.id == TipJarStore.smallTipID {
            return settings.strings.supportSmallTip
        }
        return settings.strings.supportLargeTip
    }

    private func buttonSubtitle(for option: TipJarStore.ProductOption) -> String {
        tipJarStore.title(for: option)
    }

    private var supportStatusText: String {
        let strings = settings.strings
        switch tipJarStore.purchaseResult {
        case .idle, .cancelled:
            return ""
        case .success:
            return strings.supportThankYou
        case .pending:
            return strings.supportPending
        case .unavailable:
            return strings.supportUnavailable
        case .failed:
            return strings.supportPurchaseFailed
        }
    }

    private var shouldShowSupportSection: Bool {
        true
    }
}

// MARK: - Feedback Sheet View

struct FeedbackSheetView: View {
    @Binding var feedbackText: String
    @Binding var feedbackImages: [UIImage]
    @Binding var feedbackStatus: SettingsView.FeedbackStatus
    let onSend: () -> Void

    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScreenshotItems: [PhotosPickerItem] = []

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            SkiScreenBackground {
                ScrollView {
                    VStack(spacing: 16) {
                        SkiGlassCard(cornerRadius: 28, padding: 16) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(strings.feedbackDescription)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(SkiPalette.textSecondary)

                                TextEditor(text: $feedbackText)
                                    .frame(minHeight: 150)
                                    .scrollContentBackground(.hidden)
                                    .padding(10)
                                    .foregroundStyle(SkiPalette.textPrimary)
                                    .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(SkiPalette.stroke, lineWidth: 1)
                                    )
                                    .overlay(
                                        Group {
                                            if feedbackText.isEmpty {
                                                Text(strings.feedbackPlaceholder)
                                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                                    .foregroundStyle(SkiPalette.textTertiary)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 18)
                                            }
                                        },
                                        alignment: .topLeading
                                    )
                                    .disabled(feedbackStatus == .sending || feedbackStatus == .sent)

                                VStack(alignment: .leading, spacing: 10) {
                                    PhotosPicker(
                                        selection: $selectedScreenshotItems,
                                        maxSelectionCount: 2,
                                        matching: .images
                                    ) {
                                        SkiSecondaryButtonLabel(
                                            title: strings.feedbackAddScreenshots,
                                            systemName: "photo.on.rectangle.angled"
                                        )
                                    }
                                    .disabled(feedbackStatus == .sending || feedbackStatus == .sent)

                                    if !feedbackImages.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 10) {
                                                ForEach(Array(feedbackImages.enumerated()), id: \.offset) { index, image in
                                                    ZStack(alignment: .topTrailing) {
                                                        Image(uiImage: image)
                                                            .resizable()
                                                            .scaledToFill()
                                                            .frame(width: 108, height: 108)
                                                            .clipped()
                                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                                        Button {
                                                            feedbackImages.remove(at: index)
                                                            if index < selectedScreenshotItems.count {
                                                                selectedScreenshotItems.remove(at: index)
                                                            }
                                                        } label: {
                                                            Image(systemName: "xmark.circle.fill")
                                                                .foregroundStyle(.white)
                                                                .background(Color.black.opacity(0.5), in: Circle())
                                                        }
                                                        .padding(6)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        feedbackStatusMessage

                        Button {
                            onSend()
                        } label: {
                            SkiPrimaryButtonLabel(
                                title: feedbackStatus == .sending ? strings.feedbackSending : strings.feedbackButton,
                                systemName: feedbackStatus == .sending ? nil : "paperplane.fill",
                                colors: canSend ? [SkiPalette.primary, SkiPalette.cyan] : [Color.gray.opacity(0.75), Color.gray.opacity(0.55)],
                                isLoading: feedbackStatus == .sending
                            )
                        }
                        .disabled(!canSend)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(strings.feedbackTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onChange(of: selectedScreenshotItems) { _, newItems in
                Task {
                    var loaded: [UIImage] = []
                    for item in newItems.prefix(2) {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            loaded.append(image)
                        }
                    }
                    await MainActor.run {
                        feedbackImages = loaded
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(strings.close) {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackStatusMessage: some View {
        let strings = settings.strings
        if feedbackStatus == .sent {
            statusMessage(icon: "checkmark.circle.fill", text: strings.feedbackSent, tint: SkiPalette.green)
        } else if feedbackStatus == .failed {
            statusMessage(icon: "xmark.circle.fill", text: strings.feedbackFailed, tint: SkiPalette.red)
        } else if feedbackStatus == .dailyLimitExceeded {
            statusMessage(icon: "exclamationmark.triangle.fill", text: strings.feedbackDailyLimitExceeded, tint: SkiPalette.orange)
        }
    }

    private func statusMessage(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
    }

    private var canSend: Bool {
        !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        feedbackStatus != .sending &&
        feedbackStatus != .sent &&
        feedbackStatus != .dailyLimitExceeded
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(LocationTracker())
        .environmentObject(SessionStore())
}
