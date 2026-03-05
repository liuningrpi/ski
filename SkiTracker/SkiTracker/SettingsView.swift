import SwiftUI
import CoreLocation

// MARK: - SettingsView

/// Settings screen for language, unit preferences, and account.
struct SettingsView: View {

    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var authService = AuthService.shared
    @EnvironmentObject var tracker: LocationTracker
    @EnvironmentObject var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var showLogin = false

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
            }
            .listStyle(.insetGrouped)
            .navigationTitle(strings.settings)
            .navigationBarTitleDisplayMode(.inline)
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
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(LocationTracker())
        .environmentObject(SessionStore())
}
