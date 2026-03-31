import SwiftUI
import CoreLocation
import StoreKit
import MessageUI

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

    enum FeedbackStatus {
        case idle, sending, sent, failed
    }

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            List {
                // Account Section
                AccountView()

                // Sign In button (if not logged in)
                if !authService.isLoggedIn {
                    Section {
                        Button {
                            showLogin = true
                        } label: {
                            HStack {
                                Spacer()
                                Text(strings.signIn)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                }

                // Language Section
                Section {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Button {
                            settings.language = lang
                        } label: {
                            HStack {
                                Text(lang.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if settings.language == lang {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Label(strings.languageLabel, systemImage: "globe")
                }

                // Units Section
                Section {
                    ForEach(UnitSystem.allCases, id: \.self) { unit in
                        Button {
                            settings.unitSystem = unit
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(unitDisplayName(unit))
                                        .foregroundColor(.primary)
                                    Text(unitDescription(unit))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if settings.unitSystem == unit {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Label(strings.unitsLabel, systemImage: "ruler")
                }

                // Performance Sampling Mode
                Section {
                    Toggle(isOn: $settings.performanceModeEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(strings.performanceModeTitle)
                            Text(strings.performanceModeDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label(strings.performanceSection, systemImage: "speedometer")
                }

                // Location Permission Section
                Section {
                    HStack {
                        Circle()
                            .fill(tracker.canTrack ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(permissionStatusText)
                            .foregroundColor(.secondary)
                    }

                    if tracker.authorizationStatus == .notDetermined {
                        Button {
                            tracker.requestPermission()
                        } label: {
                            HStack {
                                Image(systemName: "location.fill")
                                Text(strings.authorizeLocation)
                            }
                        }
                    }

                    if tracker.authorizationStatus == .denied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "gearshape")
                                Text(strings.goToSettings)
                            }
                        }
                    }

                if tracker.authorizationStatus == .authorizedWhenInUse {
                    Button {
                        tracker.requestAlwaysPermission()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.circle")
                                Text(requestAlwaysText)
                            }
                        }
                    }

                    Text(permissionDetailText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Label(permissionSectionTitle, systemImage: "location.circle")
                }

                if shouldShowSupportSection {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(strings.supportHeadline)
                                .font(.subheadline)
                                .foregroundColor(.primary)

                            HStack(spacing: 12) {
                                ForEach(tipJarStore.options) { option in
                                    let isPurchasing = tipJarStore.activePurchaseID == option.id
                                    Button {
                                        Task {
                                            await tipJarStore.purchase(option: option)
                                        }
                                    } label: {
                                        VStack(spacing: 4) {
                                            Text(buttonTitle(for: option))
                                                .font(.headline)
                                            Text(buttonSubtitle(for: option))
                                                .font(.caption)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isPurchasing || tipJarStore.isLoading)
                                }
                            }

                            Text(supportStatusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Label(strings.supportTitle, systemImage: "cup.and.saucer.fill")
                    }
                }

                // Feedback Section
                Section {
                    Button {
                        showFeedbackSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(strings.feedbackButton)
                                    .foregroundColor(.primary)
                                Text(strings.feedbackDescription)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label(strings.feedbackTitle, systemImage: "text.bubble")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(strings.settings)
            .navigationBarTitleDisplayMode(.inline)
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
                    feedbackStatus: $feedbackStatus,
                    onSend: sendFeedback
                )
            }
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

        // Log to Firebase
        LoggingService.shared.logFeedback(
            userId: userId,
            userEmail: userEmail,
            feedback: feedbackText,
            timestamp: timestamp
        )

        // Mark as sent (feedback is logged to Firebase)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            feedbackStatus = .sent
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showFeedbackSheet = false
                feedbackText = ""
                feedbackStatus = .idle
            }
        }
    }

    private var permissionSectionTitle: String {
        settings.language == .chinese ? "定位权限" : "Location Permission"
    }

    private var requestAlwaysText: String {
        settings.language == .chinese ? "申请“始终允许”" : "Request Always Access"
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
        case .chinese:
            return unit == .metric ? "公制" : "英制"
        case .english:
            return unit == .metric ? "Metric" : "Imperial"
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
            return strings.supportFootnote
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
    @Binding var feedbackStatus: SettingsView.FeedbackStatus
    let onSend: () -> Void

    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            VStack(spacing: 16) {
                Text(strings.feedbackDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top)

                TextEditor(text: $feedbackText)
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        Group {
                            if feedbackText.isEmpty {
                                Text(strings.feedbackPlaceholder)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 16)
                            }
                        },
                        alignment: .topLeading
                    )
                    .disabled(feedbackStatus == .sending || feedbackStatus == .sent)

                // Status message
                if feedbackStatus == .sent {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(strings.feedbackSent)
                            .foregroundColor(.green)
                    }
                    .font(.subheadline)
                } else if feedbackStatus == .failed {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(strings.feedbackFailed)
                            .foregroundColor(.red)
                    }
                    .font(.subheadline)
                }

                Spacer()

                // Send button
                Button {
                    onSend()
                } label: {
                    HStack {
                        if feedbackStatus == .sending {
                            ProgressView()
                                .tint(.white)
                            Text(strings.feedbackSending)
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text(strings.feedbackButton)
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSend ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!canSend)
                .padding(.bottom)
            }
            .padding(.horizontal)
            .navigationTitle(strings.feedbackTitle)
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

    private var canSend: Bool {
        !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        feedbackStatus != .sending &&
        feedbackStatus != .sent
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(LocationTracker())
        .environmentObject(SessionStore())
}
