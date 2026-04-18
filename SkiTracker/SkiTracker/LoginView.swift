import SwiftUI
import AuthenticationServices

// MARK: - Login View

struct LoginView: View {

    @ObservedObject var authService = AuthService.shared
    @ObservedObject var settings = SettingsManager.shared
    @EnvironmentObject var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            SkiScreenBackground {
                ScrollView {
                    VStack(spacing: 22) {
                        Spacer(minLength: 18)

                        SkiGlassCard(cornerRadius: 34, padding: 22) {
                            VStack(alignment: .center, spacing: 18) {
                                SkiIconBadge(systemName: "figure.skiing.downhill", tint: SkiPalette.primary, size: 76)

                                VStack(spacing: 8) {
                                    Text(strings.appTitle)
                                        .font(.system(size: 38, weight: .bold, design: .rounded))
                                        .foregroundStyle(SkiPalette.textPrimary)
                                        .multilineTextAlignment(.center)
                                        .minimumScaleFactor(0.72)

                                    Text(strings.welcomeMessage)
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(SkiPalette.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        SkiGlassCard(cornerRadius: 30, padding: 18) {
                            VStack(spacing: 14) {
                                SignInWithAppleButton(.signIn) { request in
                                    authService.configureAppleSignInRequest(request)
                                } onCompletion: { result in
                                    authService.handleAppleSignInResult(result)
                                }
                                .signInWithAppleButtonStyle(.black)
                                .frame(height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                                Button {
                                    authService.signInWithGoogle()
                                } label: {
                                    SkiPrimaryButtonLabel(
                                        title: strings.signInWithGoogle,
                                        systemName: "g.circle.fill",
                                        colors: [SkiPalette.red, Color(red: 0.96, green: 0.22, blue: 0.22)]
                                    )
                                }

                                if let error = authService.errorMessage {
                                    Text(error)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(SkiPalette.red)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                }

                                if authService.isSigningIn {
                                    ProgressView()
                                        .tint(SkiPalette.textPrimary)
                                        .padding(.top, 2)
                                }
                            }
                        }

                        Button {
                            dismiss()
                        } label: {
                            Text(strings.continueAsGuest)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(SkiPalette.textSecondary)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                        }

                        Spacer(minLength: 18)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(strings.close) {
                        dismiss()
                    }
                }
            }
            .onChange(of: authService.isLoggedIn) { _, isLoggedIn in
                if isLoggedIn {
                    // Save user profile to Firestore
                    if let user = authService.currentUser {
                        Task {
                            await FirestoreService.shared.saveUserProfile(user)
                            await FirestoreService.shared.uploadAllSessions(sessionStore.sessions, uid: user.uid)
                            await FriendService.shared.processPendingInviteIfNeeded(currentUser: user)
                        }
                    }
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Account View (for Settings)

struct AccountView: View {

    @ObservedObject var authService = AuthService.shared
    @ObservedObject var firestoreService = FirestoreService.shared
    @ObservedObject var settings = SettingsManager.shared
    @EnvironmentObject var sessionStore: SessionStore

    @State private var showSignOutConfirm = false

    var body: some View {
        let strings = settings.strings

        if let user = authService.currentUser {
            // Logged in state
            Section {
                // User info
                HStack(spacing: 12) {
                    SkiIconBadge(
                        systemName: user.provider == "apple" ? "apple.logo" : "g.circle.fill",
                        tint: user.provider == "apple" ? SkiPalette.textPrimary : SkiPalette.red,
                        size: 40
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName ?? user.email ?? "User")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(SkiPalette.textPrimary)
                        if let email = user.email {
                            Text(email)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(SkiPalette.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                    }
                }

                // Sync button
                Button {
                    Task {
                        await firestoreService.uploadAllSessions(sessionStore.sessions, uid: user.uid)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(firestoreService.isSyncing ? strings.syncing : strings.syncData)
                        Spacer()
                        if firestoreService.isSyncing {
                            ProgressView()
                        }
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(SkiPalette.textPrimary)
                }
                .disabled(firestoreService.isSyncing)

                // Last sync date
                if let lastSync = firestoreService.lastSyncDate {
                    HStack {
                        Text(strings.lastSynced)
                            .foregroundStyle(SkiPalette.textSecondary)
                        Spacer()
                        Text(lastSync, style: .relative)
                            .foregroundStyle(SkiPalette.textSecondary)
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                }

                // Friends
                NavigationLink {
                    FriendsView()
                } label: {
                    HStack {
                        Image(systemName: "person.2.fill")
                        Text(strings.friends)
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(SkiPalette.textPrimary)
                }

                // Sign out
                Button(role: .destructive) {
                    showSignOutConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text(strings.signOut)
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            } header: {
                Label(strings.account, systemImage: "person.circle")
            }
            .listRowBackground(Color.clear)
            .alert(strings.signOut, isPresented: $showSignOutConfirm) {
                Button(strings.cancel, role: .cancel) { }
                Button(strings.signOut, role: .destructive) {
                    authService.signOut()
                }
            }
        } else {
            // Not logged in
            Section {
                HStack(spacing: 12) {
                    SkiIconBadge(systemName: "person.crop.circle.badge.questionmark", tint: SkiPalette.textSecondary, size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(strings.dataStoredLocally)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(SkiPalette.textPrimary)
                        Text(strings.signInToSync)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(SkiPalette.textSecondary)
                    }
                }
            } header: {
                Label(strings.account, systemImage: "person.circle")
            }
            .listRowBackground(Color.clear)
        }
    }
}

// MARK: - Preview

#Preview {
    LoginView()
}
