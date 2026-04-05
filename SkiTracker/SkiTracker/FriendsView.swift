import SwiftUI
import AVFoundation
import CoreImage.CIFilterBuiltins

// MARK: - Friends View

struct FriendsView: View {

    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var authService = AuthService.shared
    @ObservedObject var friendService = FriendService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var inputCode = ""
    @State private var showScanner = false

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            List {
                if let currentUser = authService.currentUser {
                    inviteSection(user: currentUser)
                    addFriendSection(user: currentUser)
                    friendListSection(currentUser: currentUser)
                } else {
                    Section {
                        Text(strings.signInToManageFriends)
                            .foregroundColor(.secondary)
                    }
                }

                if let status = friendService.statusMessage, !status.isEmpty {
                    Section {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                if let error = friendService.errorMessage, !error.isEmpty {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(strings.friends)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(strings.close) { dismiss() }
                }
            }
            .sheet(isPresented: $showScanner) {
                ScannerContainerView { code in
                    showScanner = false
                    inputCode = code
                    if let user = authService.currentUser {
                        Task {
                            await friendService.addFriend(from: code, currentUser: user, source: "qr_scan")
                        }
                    }
                }
            }
            .task(id: authService.currentUser?.uid ?? "guest") {
                if let user = authService.currentUser {
                    await friendService.refreshFriends(uid: user.uid)
                    await friendService.processPendingInviteIfNeeded(currentUser: user)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func inviteSection(user: AppUser) -> some View {
        let strings = settings.strings

        Section(strings.myFriendQR) {
            if let link = friendService.inviteLink(for: user) {
                if let image = qrCodeImage(from: link.absoluteString) {
                    HStack {
                        Spacer()
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .padding(.vertical, 6)
                        Spacer()
                    }
                }

                Text(link.absoluteString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)

                ShareLink(item: link) {
                    Label(strings.shareInviteLink, systemImage: "square.and.arrow.up")
                }

                Button {
                    UIPasteboard.general.string = link.absoluteString
                    friendService.statusMessage = strings.inviteLinkCopied
                } label: {
                    Label(strings.copyInviteLink, systemImage: "doc.on.doc")
                }
            }
        }
    }

    @ViewBuilder
    private func addFriendSection(user: AppUser) -> some View {
        let strings = settings.strings

        Section(strings.addFriend) {
            TextField(strings.enterFriendCodeOrLink, text: $inputCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                Task {
                    await friendService.addFriend(from: inputCode, currentUser: user, source: "manual_input")
                    inputCode = ""
                }
            } label: {
                Label(strings.addByCodeOrLink, systemImage: "person.crop.circle.badge.plus")
            }

            Button {
                startQRScan()
            } label: {
                Label(strings.scanFriendQRCode, systemImage: "qrcode.viewfinder")
            }
        }
    }

    @ViewBuilder
    private func friendListSection(currentUser: AppUser) -> some View {
        let strings = settings.strings

        Section(strings.friends) {
            if friendService.isLoading {
                HStack {
                    ProgressView()
                    Text(strings.loadingFriends)
                        .foregroundColor(.secondary)
                }
            } else if friendService.friends.isEmpty {
                Text(strings.noFriendsYet)
                    .foregroundColor(.secondary)
            } else {
                ForEach(friendService.friends) { friend in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(friend.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if let email = friend.email, !email.isEmpty {
                            Text(email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if friend.isIncomingPending {
                            Text(strings.friendIncomingRequest)
                                .font(.caption2)
                                .foregroundColor(.blue)
                        } else if friend.isOutgoingPending {
                            Text(strings.friendOutgoingRequest)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else if friend.hiddenInCompetition {
                            Text(strings.friendHiddenBadge)
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if friend.isIncomingPending {
                            Button {
                                Task {
                                    await friendService.acceptFriend(friendUID: friend.uid, currentUserUID: currentUser.uid)
                                }
                            } label: {
                                Label(strings.accept, systemImage: "checkmark")
                            }
                            .tint(.green)
                        }

                        Button(role: .destructive) {
                            Task {
                                await friendService.removeFriend(friendUID: friend.uid, currentUserUID: currentUser.uid)
                            }
                        } label: {
                            Label(friend.accepted ? strings.delete : strings.decline, systemImage: "trash")
                        }

                        if friend.accepted {
                            Button {
                                Task {
                                    await friendService.setFriendHiddenInCompetition(
                                        friendUID: friend.uid,
                                        currentUserUID: currentUser.uid,
                                        hidden: !friend.hiddenInCompetition
                                    )
                                }
                            } label: {
                                let title = friend.hiddenInCompetition
                                    ? strings.unhide
                                    : strings.hide
                                Label(title, systemImage: friend.hiddenInCompetition ? "eye" : "eye.slash")
                            }
                            .tint(friend.hiddenInCompetition ? .green : .orange)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func startQRScan() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showScanner = true
                    } else {
                        friendService.errorMessage = settings.strings.cameraPermissionRequired
                    }
                }
            }
        default:
            friendService.errorMessage = settings.strings.cameraPermissionRequired
        }
    }

    private func qrCodeImage(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Scanner Container

struct ScannerContainerView: View {
    let onCodeScanned: (String) -> Void
    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QRCodeScannerView { code in
                onCodeScanned(code)
            }
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(settings.strings.close) { dismiss() }
                }
            }
        }
    }
}

// MARK: - QR Code Scanner

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCodeScanned = onCodeScanned
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) { }
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onCodeScanned: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCaptureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    private func configureCaptureSession() {
        guard let videoDevice = AVCaptureDevice.default(for: .video) else { return }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            let session = AVCaptureSession()

            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }

            let metadataOutput = AVCaptureMetadataOutput()
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            }

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)

            self.captureSession = session
            self.previewLayer = preview
            session.startRunning()
        } catch {
            // Keep scanner screen open so user can close manually
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasScanned,
              let metadata = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = metadata.stringValue else {
            return
        }

        hasScanned = true
        captureSession?.stopRunning()
        onCodeScanned?(code)
    }
}

// MARK: - Preview

#Preview {
    FriendsView()
}
