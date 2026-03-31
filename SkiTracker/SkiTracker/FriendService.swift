import Foundation
import Combine
import FirebaseFirestore

// MARK: - Friend Model

struct AppFriend: Identifiable {
    let id: String
    let uid: String
    let displayName: String
    let email: String?
    let addedAt: Date?
}

// MARK: - Friend Service

final class FriendService: ObservableObject {

    static let shared = FriendService()

    @Published var friends: [AppFriend] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var pendingInviteUID: String?

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Public API

    func inviteLink(for user: AppUser) -> URL? {
        guard let encoded = user.uid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "skitracker://add-friend?uid=\(encoded)")
    }

    func handleIncomingURL(_ url: URL) -> Bool {
        guard let friendUID = extractUID(from: url) else {
            return false
        }

        if let currentUser = AuthService.shared.currentUser {
            Task {
                await self.addFriend(friendUID: friendUID, currentUser: currentUser, source: "deep_link")
            }
        } else {
            DispatchQueue.main.async {
                self.pendingInviteUID = friendUID
                self.statusMessage = SettingsManager.shared.strings.friendInviteSavedSignInNeeded
            }
        }

        return true
    }

    func processPendingInviteIfNeeded(currentUser: AppUser) async {
        guard let friendUID = pendingInviteUID else { return }
        let succeeded = await addFriend(friendUID: friendUID, currentUser: currentUser, source: "pending_invite")
        if succeeded {
            await MainActor.run {
                self.pendingInviteUID = nil
            }
        }
    }

    func refreshFriends(uid: String) async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let snapshot = try await friendsCollection(uid: uid).getDocuments()

            let items: [AppFriend] = snapshot.documents.map { doc in
                let data = doc.data()
                let displayName = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let email = data["email"] as? String
                let addedAt = (data["addedAt"] as? Timestamp)?.dateValue()
                let name = (displayName?.isEmpty == false ? displayName : nil) ?? email ?? "User"
                return AppFriend(
                    id: doc.documentID,
                    uid: doc.documentID,
                    displayName: name,
                    email: email,
                    addedAt: addedAt
                )
            }
            .sorted { lhs, rhs in
                (lhs.addedAt ?? .distantPast) > (rhs.addedAt ?? .distantPast)
            }

            await MainActor.run {
                self.friends = items
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                if self.isOfflineFirestoreError(error) {
                    self.errorMessage = SettingsManager.shared.strings.friendOfflineRefresh
                } else {
                    self.errorMessage = error.localizedDescription
                }
                self.isLoading = false
            }
        }
    }

    @discardableResult
    func addFriend(from input: String, currentUser: AppUser, source: String) async -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        guard let uid = extractUID(from: trimmed) else {
            await MainActor.run {
                self.errorMessage = SettingsManager.shared.strings.friendInvalidInvite
            }
            return false
        }

        return await addFriend(friendUID: uid, currentUser: currentUser, source: source)
    }

    @discardableResult
    func addFriend(friendUID: String, currentUser: AppUser, source: String) async -> Bool {
        let strings = SettingsManager.shared.strings

        if friendUID == currentUser.uid {
            await MainActor.run {
                self.errorMessage = strings.friendCannotAddSelf
            }
            return false
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let targetDoc = try await userDocument(uid: friendUID).getDocument()
            guard targetDoc.exists else {
                await MainActor.run {
                    self.errorMessage = strings.friendAccountNotFound
                    self.isLoading = false
                }
                return false
            }

            let currentDoc = try await userDocument(uid: currentUser.uid).getDocument()

            let targetData = targetDoc.data() ?? [:]
            let targetName = (targetData["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetEmail = targetData["email"] as? String
            let finalTargetName = (targetName?.isEmpty == false ? targetName : nil) ?? targetEmail ?? "User"

            let currentData = currentDoc.data() ?? [:]
            let currentNameRaw = (currentData["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentName = (currentNameRaw?.isEmpty == false ? currentNameRaw : nil) ?? currentUser.displayName ?? currentUser.email ?? "User"
            let currentEmail = (currentData["email"] as? String) ?? currentUser.email

            let batch = db.batch()

            let currentToFriendRef = friendsCollection(uid: currentUser.uid).document(friendUID)
            let friendToCurrentRef = friendsCollection(uid: friendUID).document(currentUser.uid)

            batch.setData([
                "uid": friendUID,
                "displayName": finalTargetName,
                "email": targetEmail ?? "",
                "accepted": true,
                "addedAt": FieldValue.serverTimestamp(),
                "source": source
            ], forDocument: currentToFriendRef, merge: true)

            batch.setData([
                "uid": currentUser.uid,
                "displayName": currentName,
                "email": currentEmail ?? "",
                "accepted": true,
                "addedAt": FieldValue.serverTimestamp(),
                "source": source
            ], forDocument: friendToCurrentRef, merge: true)

            try await batch.commit()
            await refreshFriends(uid: currentUser.uid)

            await MainActor.run {
                self.statusMessage = "\(strings.friendAdded): \(finalTargetName)"
                self.isLoading = false
            }
            return true
        } catch {
            await MainActor.run {
                if self.isOfflineFirestoreError(error) {
                    self.pendingInviteUID = friendUID
                    self.errorMessage = nil
                    self.statusMessage = strings.friendOfflineQueued
                } else {
                    self.errorMessage = error.localizedDescription
                }
                self.isLoading = false
            }
            return false
        }
    }

    // MARK: - Parsing

    private func extractUID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if let url = URL(string: trimmed), let uid = extractUID(from: url) {
            return uid
        }

        if trimmed.contains("uid="), let components = URLComponents(string: trimmed),
           let uid = components.queryItems?.first(where: { $0.name == "uid" })?.value,
           !uid.isEmpty {
            return uid
        }

        return trimmed
    }

    private func extractUID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()

        if url.scheme?.lowercased() == "skitracker" && (host == "add-friend" || path.contains("add-friend")) {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let uid = components.queryItems?.first(where: { $0.name == "uid" })?.value,
               !uid.isEmpty {
                return uid
            }
        }

        if host.contains("skitracker.app") && path.contains("add-friend") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let uid = components.queryItems?.first(where: { $0.name == "uid" })?.value,
               !uid.isEmpty {
                return uid
            }
        }

        return nil
    }

    // MARK: - Firestore

    private func userDocument(uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    private func friendsCollection(uid: String) -> CollectionReference {
        userDocument(uid: uid).collection("friends")
    }

    private func isOfflineFirestoreError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain {
            return nsError.code == FirestoreErrorCode.unavailable.rawValue ||
                nsError.code == FirestoreErrorCode.deadlineExceeded.rawValue
        }
        return nsError.localizedDescription.lowercased().contains("client is offline")
    }
}
