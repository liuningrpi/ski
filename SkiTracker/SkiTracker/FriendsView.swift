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
            SkiScreenBackground {
                List {
                    if let currentUser = authService.currentUser {
                        inviteSection(user: currentUser)
                        addFriendSection(user: currentUser)
                        friendListSection(currentUser: currentUser)
                    } else if !authService.isAuthStateResolved {
                        Section {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(SkiPalette.textPrimary)
                                Text(strings.loadingFriends)
                                    .foregroundStyle(SkiPalette.textSecondary)
                            }
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        Section {
                            Text(strings.signInToManageFriends)
                                .foregroundStyle(SkiPalette.textSecondary)
                        }
                        .listRowBackground(Color.clear)
                    }

                    if let status = friendService.statusMessage, !status.isEmpty {
                        Section {
                            Text(status)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(SkiPalette.green)
                        }
                        .listRowBackground(Color.clear)
                    }

                    if let error = friendService.errorMessage, !error.isEmpty {
                        Section {
                            Text(error)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(SkiPalette.red)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle(strings.friends)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                    .foregroundStyle(SkiPalette.textSecondary)
                    .textSelection(.enabled)

                ShareLink(item: link) {
                    SkiSecondaryButtonLabel(title: strings.shareInviteLink, systemName: "square.and.arrow.up")
                }

                Button {
                    UIPasteboard.general.string = link.absoluteString
                    friendService.statusMessage = strings.inviteLinkCopied
                } label: {
                    SkiSecondaryButtonLabel(title: strings.copyInviteLink, systemName: "doc.on.doc")
                }
            }
        }
        .listRowBackground(Color.clear)
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
                SkiPrimaryButtonLabel(title: strings.addByCodeOrLink, systemName: "person.crop.circle.badge.plus")
            }

            Button {
                startQRScan()
            } label: {
                SkiSecondaryButtonLabel(title: strings.scanFriendQRCode, systemName: "qrcode.viewfinder")
            }
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func friendListSection(currentUser: AppUser) -> some View {
        let strings = settings.strings

        Section(strings.friends) {
            if friendService.isLoading {
                HStack {
                    ProgressView()
                        .tint(SkiPalette.textPrimary)
                    Text(strings.loadingFriends)
                        .foregroundStyle(SkiPalette.textSecondary)
                }
            } else if friendService.friends.isEmpty {
                Text(strings.noFriendsYet)
                    .foregroundStyle(SkiPalette.textSecondary)
            } else {
                ForEach(friendService.friends) { friend in
                    HStack {
                        Text(friend.displayName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(SkiPalette.textPrimary)
                        Spacer()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task {
                                await friendService.removeFriend(friendUID: friend.uid, currentUserUID: currentUser.uid)
                            }
                        } label: {
                            Label(strings.delete, systemImage: "trash")
                        }

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
        .listRowBackground(Color.clear)
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
