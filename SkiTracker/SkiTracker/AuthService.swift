import Foundation
import SwiftUI
import Combine
import AuthenticationServices
import CryptoKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

// MARK: - User Model

struct AppUser: Codable, Equatable {
    let uid: String
    let email: String?
    let displayName: String?
    let photoURL: String?
    let provider: String // "apple" or "google"

    init(from firebaseUser: FirebaseAuth.User, provider: String) {
        self.uid = firebaseUser.uid
        self.email = firebaseUser.email
        self.displayName = firebaseUser.displayName
        self.photoURL = firebaseUser.photoURL?.absoluteString
        self.provider = provider
    }
}

// MARK: - Auth Service

final class AuthService: NSObject, ObservableObject {

    static let shared = AuthService()

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

    func signInWithApple() {
        let nonce = randomNonceString()
        currentNonce = nonce
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.performRequests()

        isSigningIn = true
        errorMessage = nil
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

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
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
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        DispatchQueue.main.async { [weak self] in
            self?.isSigningIn = false

            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                self?.errorMessage = "Invalid Apple credential"
                return
            }

            guard let nonce = self?.currentNonce else {
                self?.errorMessage = "Invalid state: nonce not found"
                return
            }

            guard let appleIDToken = appleIDCredential.identityToken else {
                self?.errorMessage = "Unable to fetch identity token"
                return
            }

            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                self?.errorMessage = "Unable to serialize token string"
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
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

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isSigningIn = false
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                self?.errorMessage = error.localizedDescription
            }
        }
    }
}
