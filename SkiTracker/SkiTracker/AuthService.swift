import Foundation
import SwiftUI
import Combine
import AuthenticationServices
import CryptoKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
import os.log

// MARK: - User Model

struct AppUser: Codable, Equatable {
    let uid: String
    let email: String?
    let displayName: String?
    let photoURL: String?
    let provider: String // "apple" or "google"

    init(from firebaseUser: FirebaseAuth.User, provider: String) {
        let rawDisplayName = firebaseUser.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayName: String? = {
            if let rawDisplayName, !rawDisplayName.isEmpty {
                return rawDisplayName
            }
            guard let email = firebaseUser.email else { return nil }
            if email.localizedCaseInsensitiveContains("privaterelay.appleid.com") {
                return "Skier"
            }
            return nil
        }()

        self.uid = firebaseUser.uid
        self.email = firebaseUser.email
        self.displayName = resolvedDisplayName
        self.photoURL = firebaseUser.photoURL?.absoluteString
        self.provider = provider
    }
}

// MARK: - Auth Service

final class AuthService: NSObject, ObservableObject {

    static let shared = AuthService()
    private static let logger = Logger(subsystem: "com.nliu.SkiTracker", category: "AuthService")

    let objectWillChange = ObservableObjectPublisher()
    private let cachedUserDefaultsKey = "auth_cached_user_v1"

    var currentUser: AppUser? {
        didSet {
            cacheCurrentUser()
            objectWillChange.send()
        }
    }
    var isAuthStateResolved: Bool = false {
        didSet { objectWillChange.send() }
    }
    var isSigningIn: Bool = false {
        didSet { objectWillChange.send() }
    }
    var errorMessage: String? {
        didSet { objectWillChange.send() }
    }

    // For Apple Sign-In
    private var currentNonce: String?
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    private override init() {
        super.init()

        // Warm start: use locally cached user to avoid login flicker while Firebase restores auth state.
        if let cachedUser = loadCachedUser() {
            currentUser = cachedUser
        }

        // Prefer Firebase persisted auth if already available at launch.
        if let firebaseUser = Auth.auth().currentUser {
            currentUser = AppUser(from: firebaseUser, provider: providerName(for: firebaseUser))
        }

        // Listen to auth state changes
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                if let user = user {
                    self?.currentUser = AppUser(from: user, provider: self?.providerName(for: user) ?? "unknown")
                } else {
                    self?.currentUser = nil
                }
                self?.isAuthStateResolved = true
            }
        }
    }

    var isLoggedIn: Bool {
        currentUser != nil
    }

    // MARK: - Apple Sign-In

    func configureAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        guard let nonce = randomNonceString() else {
            isSigningIn = false
            errorMessage = "Unable to start Apple sign-in. Please try again."
            print("[AppleSignIn] failed to generate nonce")
            return
        }
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        isSigningIn = true
        errorMessage = nil
        print("[AppleSignIn] configure request nonce_set=true")
    }

    func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            print("[AppleSignIn] completion success from SignInWithAppleButton")
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                DispatchQueue.main.async { [weak self] in
                    self?.isSigningIn = false
                    self?.errorMessage = "Invalid Apple credential"
                }
                print("[AppleSignIn] invalid credential type in completion")
                return
            }
            signInWithFirebase(appleIDCredential: appleIDCredential)
        case .failure(let error):
            print("[AppleSignIn] completion failure from SignInWithAppleButton: \(error)")
            handleAppleSignInError(error)
        }
    }

    func signInWithApple() {
        print("[AppleSignIn] signInWithApple() invoked")
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        configureAppleSignInRequest(request)

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() {
        let plistClientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        guard let clientID = FirebaseApp.app()?.options.clientID ?? plistClientID, !clientID.isEmpty else {
            errorMessage = "Firebase configuration error"
            print("[GoogleSignIn] missing clientID in FirebaseApp/Info.plist")
            return
        }

        print("[GoogleSignIn] starting Google sign-in")
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        DispatchQueue.main.async { [weak self] in
            guard let rootViewController = self?.activePresentationController() else {
                self?.errorMessage = "Cannot find root view controller"
                print("[GoogleSignIn] failed to find active presentation controller")
                return
            }

            self?.isSigningIn = true
            self?.errorMessage = nil

            GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] result, error in
                DispatchQueue.main.async {
                    self?.isSigningIn = false

                    if let error = error {
                        print("[GoogleSignIn] Google SDK sign-in error: \(error.localizedDescription)")
                        self?.errorMessage = self?.friendlyGoogleErrorMessage(error) ?? error.localizedDescription
                        return
                    }

                    guard let user = result?.user,
                          let idToken = user.idToken?.tokenString else {
                        self?.errorMessage = "Failed to get Google credentials"
                        print("[GoogleSignIn] sign-in completed without usable token")
                        return
                    }

                    let credential = GoogleAuthProvider.credential(
                        withIDToken: idToken,
                        accessToken: user.accessToken.tokenString
                    )

                    Auth.auth().signIn(with: credential) { _, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                print("[GoogleSignIn] Firebase sign-in error: \(error.localizedDescription)")
                                self?.errorMessage = self?.friendlyGoogleFirebaseErrorMessage(error) ?? error.localizedDescription
                            } else {
                                print("[GoogleSignIn] Firebase sign-in success")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            currentUser = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helper Functions

    private func randomNonceString(length: Int = 32) -> String? {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            Self.logger.error("Nonce generation failed with OSStatus \(errorCode, privacy: .public)")
            return nil
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }

    private func activePresentationController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        let windows = scenes.flatMap(\.windows)
        let rootViewController = windows.first(where: \.isKeyWindow)?.rootViewController
            ?? windows.first?.rootViewController

        guard let rootViewController else {
            return nil
        }

        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }
        return topController
    }

    private func providerName(for user: FirebaseAuth.User) -> String {
        let provider = user.providerData.first?.providerID ?? "unknown"
        if provider.contains("apple") { return "apple" }
        if provider.contains("google") { return "google" }
        return provider
    }

    private func cacheCurrentUser() {
        let defaults = UserDefaults.standard
        guard let currentUser else {
            defaults.removeObject(forKey: cachedUserDefaultsKey)
            return
        }

        do {
            let data = try JSONEncoder().encode(currentUser)
            defaults.set(data, forKey: cachedUserDefaultsKey)
        } catch {
            defaults.removeObject(forKey: cachedUserDefaultsKey)
        }
    }

    private func loadCachedUser() -> AppUser? {
        guard let data = UserDefaults.standard.data(forKey: cachedUserDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AppUser.self, from: data)
    }

    private func friendlyGoogleErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == "com.google.GIDSignIn" {
            switch nsError.code {
            case GIDSignInError.canceled.rawValue:
                return "Google sign-in was canceled."
            case GIDSignInError.hasNoAuthInKeychain.rawValue:
                return "No Google session found. Please sign in again."
            case GIDSignInError.EMM.rawValue:
                return "Google sign-in is blocked by device policy."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private func friendlyGoogleFirebaseErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain else {
            return error.localizedDescription
        }

        switch AuthErrorCode(rawValue: nsError.code) {
        case .operationNotAllowed:
            return "Google sign-in is not enabled in Firebase Authentication."
        case .invalidCredential:
            return "Google credential was rejected. Check the Firebase iOS OAuth configuration."
        case .accountExistsWithDifferentCredential:
            return "An account already exists with a different sign-in method."
        case .networkError:
            return "Network error during Google sign-in. Please try again."
        default:
            return error.localizedDescription
        }
    }

    private func signInWithFirebase(appleIDCredential: ASAuthorizationAppleIDCredential) {
        print("[AppleSignIn] exchanging Apple credential with Firebase")
        guard let nonce = self.currentNonce else {
            DispatchQueue.main.async { [weak self] in
                self?.isSigningIn = false
                self?.errorMessage = "Invalid state: nonce not found"
            }
            print("[AppleSignIn] missing nonce")
            return
        }

        guard let appleIDToken = appleIDCredential.identityToken else {
            DispatchQueue.main.async { [weak self] in
                self?.isSigningIn = false
                self?.errorMessage = "Unable to fetch identity token"
            }
            print("[AppleSignIn] missing identity token")
            return
        }

        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            DispatchQueue.main.async { [weak self] in
                self?.isSigningIn = false
                self?.errorMessage = "Unable to serialize token string"
            }
            print("[AppleSignIn] cannot serialize identity token")
            return
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )

        Auth.auth().signIn(with: credential) { [weak self] _, error in
            DispatchQueue.main.async {
                self?.isSigningIn = false
                if let error = error {
                    let nsError = error as NSError
                    self?.errorMessage = error.localizedDescription
                    print("[AppleSignIn] Firebase signIn error domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")
                } else {
                    self?.applyPreferredAppleDisplayName(from: appleIDCredential)
                    print("[AppleSignIn] Firebase signIn success")
                }
            }
        }
    }

    private func applyPreferredAppleDisplayName(from credential: ASAuthorizationAppleIDCredential) {
        guard let user = Auth.auth().currentUser else { return }

        let formatter = PersonNameComponentsFormatter()
        let formattedName = credential.fullName.flatMap { formatter.string(from: $0).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let formattedName, !formattedName.isEmpty else { return }
        guard (user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else { return }

        let request = user.createProfileChangeRequest()
        request.displayName = formattedName
        request.commitChanges { error in
            if let error {
                print("[AppleSignIn] failed to set display name: \(error.localizedDescription)")
            } else {
                print("[AppleSignIn] display name updated to '\(formattedName)'")
            }
        }
    }

    private func handleAppleSignInError(_ error: Error) {
        let nsError = error as NSError
        Self.logger.error(
            "Apple Sign-In failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) message=\(nsError.localizedDescription, privacy: .public)"
        )
        print("[AppleSignIn] failed domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")

        DispatchQueue.main.async { [weak self] in
            self?.isSigningIn = false
            if nsError.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            if nsError.domain == ASAuthorizationError.errorDomain &&
                nsError.code == ASAuthorizationError.unknown.rawValue {
                self?.errorMessage = "Apple sign-in unavailable (\(nsError.domain):\(nsError.code)). Check team provisioning, Sign in with Apple capability, and iCloud login."
                return
            }
            self?.errorMessage = "\(nsError.localizedDescription) (\(nsError.domain):\(nsError.code))"
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        print("[AppleSignIn] ASAuthorizationController success callback")
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            DispatchQueue.main.async { [weak self] in
                self?.isSigningIn = false
                self?.errorMessage = "Invalid Apple credential"
            }
            print("[AppleSignIn] invalid credential type in controller callback")
            return
        }
        signInWithFirebase(appleIDCredential: appleIDCredential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("[AppleSignIn] ASAuthorizationController error callback: \(error)")
        handleAppleSignInError(error)
    }
}

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let resolvedScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first

        guard let windowScene = resolvedScene else {
            preconditionFailure("No UIWindowScene available for Apple Sign-In presentation anchor.")
        }
        if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        if let firstWindow = windowScene.windows.first {
            return firstWindow
        }
        return UIWindow(windowScene: windowScene)
    }
}
