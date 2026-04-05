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

    var currentUser: AppUser? {
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
        // Listen to auth state changes
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                if let user = user {
                    // Determine provider
                    let provider = user.providerData.first?.providerID ?? "unknown"
                    let providerName = provider.contains("apple") ? "apple" : (provider.contains("google") ? "google" : provider)
                    self?.currentUser = AppUser(from: user, provider: providerName)
                } else {
                    self?.currentUser = nil
                }
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
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Firebase configuration error"
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        DispatchQueue.main.async { [weak self] in
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                self?.errorMessage = "Cannot find root view controller"
                return
            }

            self?.isSigningIn = true
            self?.errorMessage = nil

            GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] result, error in
                DispatchQueue.main.async {
                    self?.isSigningIn = false

                    if let error = error {
                        self?.errorMessage = error.localizedDescription
                        return
                    }

                    guard let user = result?.user,
                          let idToken = user.idToken?.tokenString else {
                        self?.errorMessage = "Failed to get Google credentials"
                        return
                    }

                    let credential = GoogleAuthProvider.credential(
                        withIDToken: idToken,
                        accessToken: user.accessToken.tokenString
                    )

                    Auth.auth().signIn(with: credential) { _, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self?.errorMessage = error.localizedDescription
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
