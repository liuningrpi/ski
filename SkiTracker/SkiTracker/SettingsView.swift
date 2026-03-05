import SwiftUI

// MARK: - SettingsView

/// Settings screen for language, unit preferences, and account.
struct SettingsView: View {

    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var authService = AuthService.shared
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
        .environmentObject(SessionStore())
}
