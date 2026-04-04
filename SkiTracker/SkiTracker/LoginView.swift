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
            VStack(spacing: 32) {
                Spacer()

                // App Icon & Title
                VStack(spacing: 16) {
                    Image(systemName: "figure.skiing.downhill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)

                    Text(strings.appTitle)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(strings.welcomeMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // Sign In Buttons
                VStack(spacing: 16) {
                    // Apple Sign In
                    SignInWithAppleButton(.signIn) { request in
                        authService.configureAppleSignInRequest(request)
                    } onCompletion: { result in
                        authService.handleAppleSignInResult(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(12)

                    // Google Sign In
                    Button {
                        authService.signInWithGoogle()
                    } label: {
                        HStack {
                            Image(systemName: "g.circle.fill")
                                .font(.title2)
                            Text(strings.signInWithGoogle)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.red)
                        .cornerRadius(12)
                    }

                    // Error message
                    if let error = authService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    // Loading indicator
                    if authService.isSigningIn {
                        ProgressView()
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 32)

                // Continue as Guest
                Button {
                    dismiss()
                } label: {
                    Text(strings.continueAsGuest)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
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
                HStack {
                    Image(systemName: user.provider == "apple" ? "apple.logo" : "g.circle.fill")
                        .font(.title2)
                        .foregroundColor(user.provider == "apple" ? .primary : .red)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName ?? user.email ?? "User")
                            .font(.headline)
                        if let email = user.email {
                            Text(email)
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                }
                .disabled(firestoreService.isSyncing)

                // Last sync date
                if let lastSync = firestoreService.lastSyncDate {
                    HStack {
                        Text(strings.lastSynced)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(lastSync, style: .relative)
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }

                // Friends
                NavigationLink {
                    FriendsView()
                } label: {
                    HStack {
                        Image(systemName: "person.2.fill")
                        Text(strings.friends)
                    }
                }

                // Sign out
                Button(role: .destructive) {
                    showSignOutConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text(strings.signOut)
                    }
                }
            } header: {
                Label(strings.account, systemImage: "person.circle")
            }
            .alert(strings.signOut, isPresented: $showSignOutConfirm) {
                Button(strings.cancel, role: .cancel) { }
                Button(strings.signOut, role: .destructive) {
                    authService.signOut()
                }
            }
        } else {
            // Not logged in
            Section {
                HStack {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(strings.dataStoredLocally)
                            .font(.subheadline)
                        Text(strings.signInToSync)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Label(strings.account, systemImage: "person.circle")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LoginView()
}
