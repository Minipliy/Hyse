import SwiftUI
import AVFoundation

struct BarcodeScannerView: UIViewControllerRepresentable {
    @Binding var torchOn: Bool
    var onScanned: (String) -> Void
    var onError: (String) -> Void
    /// AVCaptureSession start/stop calls may block. Keep every camera-session
    /// operation off the main thread and in order, especially while a sheet is
    /// being dismissed immediately after opening the scanner.
    private static let captureSessionQueue = DispatchQueue(label: "com.hyse.barcode.capture-session")

    // Custom controller to keep the layer matched to the view bounds on layout changes
    class ScannerViewController: UIViewController {
        var previewLayer: AVCaptureVideoPreviewLayer?
        var captureSession: AVCaptureSession?
        var captureDevice: AVCaptureDevice?

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        func setTorch(_ enabled: Bool) {
            guard let captureDevice, captureDevice.hasTorch else { return }
            BarcodeScannerView.captureSessionQueue.async {
                do {
                    try captureDevice.lockForConfiguration()
                    captureDevice.torchMode = enabled ? .on : .off
                    captureDevice.unlockForConfiguration()
                } catch { }
            }
        }
    }

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: BarcodeScannerView
        var isScanned = false

        init(parent: BarcodeScannerView) {
            self.parent = parent
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !isScanned else { return }

            if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
               let stringValue = metadataObject.stringValue {
                isScanned = true
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                DispatchQueue.main.async {
                    self.parent.onScanned(stringValue)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = ScannerViewController()
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        viewController.captureSession = captureSession

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            DispatchQueue.main.async {
                onError(LanguageStore.localizedString("barcode.camera_unavailable"))
            }
            return viewController
        }
        viewController.captureDevice = videoCaptureDevice

        do {
            try videoCaptureDevice.lockForConfiguration()
            if videoCaptureDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoCaptureDevice.focusMode = .continuousAutoFocus
            }
            if videoCaptureDevice.isFocusPointOfInterestSupported {
                videoCaptureDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if videoCaptureDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoCaptureDevice.exposureMode = .continuousAutoExposure
            }
            if videoCaptureDevice.isAutoFocusRangeRestrictionSupported {
                videoCaptureDevice.autoFocusRangeRestriction = .near
            }
            videoCaptureDevice.unlockForConfiguration()
        } catch { }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            DispatchQueue.main.async {
                onError(LanguageStore.localizedString("barcode.camera_initialization_failed"))
            }
            return viewController
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            DispatchQueue.main.async {
                onError(LanguageStore.localizedString("barcode.camera_input_unsupported"))
            }
            return viewController
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce, .code128]
        } else {
            DispatchQueue.main.async {
                onError(LanguageStore.localizedString("barcode.output_failed"))
            }
            return viewController
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = viewController.view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        viewController.view.layer.addSublayer(previewLayer)
        viewController.previewLayer = previewLayer

        Self.captureSessionQueue.async {
            captureSession.startRunning()
        }

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? ScannerViewController)?.setTorch(torchOn)
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        guard let controller = uiViewController as? ScannerViewController else { return }
        let session = controller.captureSession
        controller.setTorch(false)
        captureSessionQueue.async {
            guard let session, session.isRunning else { return }
            session.stopRunning()
        }
    }
}

struct BarcodeInputField: View {
    @EnvironmentObject private var language: LanguageStore
    @Binding var barcode: String
    @State private var showingScanner = false
    @State private var showingCameraExplanation = false
    @State private var showingCameraDenied = false
    @State private var torchOn = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: HyseSpacing.small) {
            TextField(language.text("ui.barcode_optional"), text: $barcode)
                .keyboardType(.numberPad)
            Button(action: beginScan) {
                Image(systemName: "barcode.viewfinder")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("ui.scan_barcode"))
        }
        .sheet(isPresented: $showingScanner) {
            NavigationStack {
                BarcodeScannerView(
                    torchOn: $torchOn,
                    onScanned: { value in
                        do { barcode = try BarcodeNormalizer.normalize(value) }
                        catch { errorMessage = error.localizedDescription }
                        showingScanner = false
                    },
                    onError: { message in errorMessage = message; showingScanner = false }
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 280, height: 170)
                        .shadow(color: .black.opacity(0.55), radius: 5)
                }
                .safeAreaInset(edge: .bottom) {
                    Button { torchOn.toggle() } label: {
                        Label(language.text("barcode.flashlight"), systemImage: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(HyseColor.background)
                }
                .navigationTitle(language.text("ui.scan_barcode"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(language.text("app_tabs.cancel")) { showingScanner = false }
                    }
                }
            }
        }
        .alert(language.text("barcode.camera_permission_title"), isPresented: $showingCameraExplanation) {
            Button(language.text("app_tabs.cancel"), role: .cancel) {}
            Button(language.text("barcode.allow_camera")) { requestCameraAccess() }
        } message: { Text(language.text("barcode.camera_permission_explanation")) }
        .alert(language.text("barcode.camera_permission_denied_title"), isPresented: $showingCameraDenied) {
            Button(language.text("app_tabs.cancel"), role: .cancel) {}
            Button(language.text("barcode.open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        } message: { Text(language.text("barcode.camera_permission_denied_message")) }
        .alert(language.text("ui.notice"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(language.text("common.ok")) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func beginScan() {
        torchOn = false
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showingScanner = true
        case .notDetermined: showingCameraExplanation = true
        case .denied, .restricted: showingCameraDenied = true
        @unknown default: showingCameraDenied = true
        }
    }

    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted { showingScanner = true }
                else { showingCameraDenied = true }
            }
        }
    }
}
