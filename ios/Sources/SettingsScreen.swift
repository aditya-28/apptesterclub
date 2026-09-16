import SwiftUI
import AVFoundation
import UserNotifications

struct SettingsScreen: View {
    let store: ServerStore
    @State private var isScanning = false
    @State private var manualURL = ""
    @State private var manualToken = ""
    @State private var manualName = ""
    @State private var renaming: Server?
    @State private var scanFailure: String?

    var body: some View {
        Form {
            Section {
                if store.servers.isEmpty {
                    Text("No servers yet. Scan the pairing code on your AppTesterClub instance, or enter the details below.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Palette.textTertiary)
                } else {
                    ForEach(store.servers) { server in
                        Button {
                            store.select(server)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.displayName)
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(Palette.textPrimary)
                                    Text(server.url.absoluteString)
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundStyle(Palette.textTertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                if store.selected?.id == server.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.accent)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .swipeActions(edge: .leading) {
                            Button { renaming = server } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(Palette.accent)
                        }
                        .contextMenu {
                            Button { renaming = server } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { store.servers[$0] }.forEach(store.remove)
                    }
                    .onMove { _, _ in }
                }
            } header: {
                Text("Servers")
            } footer: {
                Text("Several at once is supported: your own instance and a client's, each with its own builds.")
            }

            Section {
                Button {
                    scanFailure = nil
                    isScanning = true
                } label: {
                    Label("Scan pairing code", systemImage: "qrcode.viewfinder")
                }

                if let scanFailure {
                    Text(scanFailure)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Palette.danger)
                }
            } header: {
                Text("Add a server")
            } footer: {
                Text("Open /pair on your instance and scan what it shows. Beats typing a 48-character token on a phone.")
            }

            Section("Or enter it by hand") {
                TextField("Name (optional)", text: $manualName)
                    .autocorrectionDisabled()

                TextField("https://builds.example.com", text: $manualURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                SecureField("Access token", text: $manualToken)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button("Add server") { addManual() }
                    .disabled(URL(string: manualURL)?.scheme != "https" || manualToken.isEmpty)
            }

            Section {
                LabeledContent("Permission") {
                    Text(permissionText)
                        .foregroundStyle(permissionColor)
                }
                LabeledContent("This device") {
                    Text(Push.shared.token == nil ? "Not registered" : "Registered")
                        .foregroundStyle(Push.shared.token == nil ? Palette.warning : Palette.success)
                }
                if Push.shared.token != nil {
                    Button("Re-register with all servers") {
                        Task { await Push.shared.register(with: store.servers) }
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("A build pushed to any server you are paired with arrives here. The server also needs an Apple push key configured, or nothing is sent.")
            }

            Section {
                LabeledContent("Version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                        .monospacedDigit()
                }
                Link("Source and documentation",
                     destination: URL(string: "https://github.com/aditya-28/apptesterclub")!)
            } footer: {
                Text("AppTesterClub is open source. You built and signed this copy yourself, and it talks only to the servers listed above.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await Push.shared.refreshAuthorization() }
        .sheet(item: $renaming) { server in
            RenameServerSheet(store: store, server: server)
        }
        .sheet(isPresented: $isScanning) {
            QRScanner { url in
                isScanning = false
                guard let server = PairingLink.parse(url) else {
                    scanFailure = "That is not an AppTesterClub pairing code, or its address is not HTTPS."
                    return
                }
                store.add(server)
            }
        }
    }

    private var permissionText: String {
        switch Push.shared.authorization {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Denied in Settings"
        default: "Not asked yet"
        }
    }

    private var permissionColor: Color {
        switch Push.shared.authorization {
        case .authorized, .provisional, .ephemeral: Palette.success
        case .denied: Palette.danger
        default: Palette.textTertiary
        }
    }

    private func addManual() {
        guard let url = URL(string: manualURL), url.scheme == "https" else { return }
        let name = manualName.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = Server(name: name.isEmpty ? (url.host() ?? "") : name,
                            url: url, token: manualToken)
        store.add(server)
        Task { await Push.shared.register(with: server) }
        manualURL = ""
        manualToken = ""
        manualName = ""
    }
}

/// Minimal QR reader. It wants exactly one payload — a pairing link — so it
/// hands back the first valid URL it sees and closes.
struct QRScanner: UIViewControllerRepresentable {
    let onFound: (URL) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        ScannerController(onFound: onFound)
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

@MainActor
final class ScannerController: UIViewController {
    private let onFound: (URL) -> Void
    private var delivered = false
    private var forwarder: MetadataForwarder?

    /// AVCaptureSession is documented as safe to start and stop from a
    /// background queue, which is required because both calls block. Swift 6
    /// cannot see that guarantee, hence the explicit opt-out rather than
    /// pretending the type is Sendable.
    private nonisolated(unsafe) let session = AVCaptureSession()
    private nonisolated(unsafe) static let queue = DispatchQueue(label: "club.apptester.capture")

    init(onFound: @escaping (URL) -> Void) {
        self.onFound = onFound
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        let forwarder = MetadataForwarder { [weak self] url in self?.deliver(url) }
        self.forwarder = forwarder
        output.setMetadataObjectsDelegate(forwarder, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)

        let session = self.session
        Self.queue.async { session.startRunning() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let session = self.session
        Self.queue.async { session.stopRunning() }
    }

    /// The capture output fires repeatedly while a code is in frame; the sheet
    /// should act on the first one only.
    private func deliver(_ url: URL) {
        guard !delivered else { return }
        delivered = true
        onFound(url)
    }
}

/// AVFoundation's delegate protocol is not main-actor isolated and a
/// UIViewController is, so the conformance cannot sit on the controller under
/// Swift 6. This forwarder is deliberately separate; the output queue is
/// `.main`, which `assumeIsolated` asserts rather than assumes.
private final class MetadataForwarder: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private let handler: @MainActor (URL) -> Void

    init(handler: @escaping @MainActor (URL) -> Void) {
        self.handler = handler
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput objects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            let object = objects.first as? AVMetadataMachineReadableCodeObject,
            let value = object.stringValue,
            let url = URL(string: value)
        else { return }
        // Copy out of self first: capturing the property would send the whole
        // object across the isolation boundary, which Swift 6 rejects.
        let handler = self.handler
        MainActor.assumeIsolated { handler(url) }
    }
}
