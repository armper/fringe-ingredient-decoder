import AVFoundation
import SwiftUI

struct BarcodeScannerView: UIViewRepresentable {
    let isRunning: Bool
    let onCodeDetected: (String) -> Void
    let onStateChanged: (DecoderStore.CameraState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeDetected: onCodeDetected, onStateChanged: onStateChanged)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        context.coordinator.attach(to: view)
        context.coordinator.configureIfNeeded()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.attach(to: uiView)
        context.coordinator.setRunning(isRunning)
    }
}

final class PreviewView: UIView {
    #if !targetEnvironment(simulator)
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
    #endif
}

extension BarcodeScannerView {
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private var session: AVCaptureSession?
        private let sessionQueue = DispatchQueue(label: "FringeIngredientDecoder.ScannerSession")
        private var metadataOutput: AVCaptureMetadataOutput?
        private let onCodeDetected: (String) -> Void
        private let onStateChanged: (DecoderStore.CameraState) -> Void

        private weak var previewView: PreviewView?
        private var isConfigured = false
        private var wantsRunning = true
        private var lastCode = ""
        private var lastDetection = Date.distantPast

        init(
            onCodeDetected: @escaping (String) -> Void,
            onStateChanged: @escaping (DecoderStore.CameraState) -> Void
        ) {
            self.onCodeDetected = onCodeDetected
            self.onStateChanged = onStateChanged
        }

        func attach(to view: PreviewView) {
            previewView = view
            #if !targetEnvironment(simulator)
            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill
            #endif
        }

        func configureIfNeeded() {
            guard !isConfigured else { return }

            if isSimulatorEnvironment {
                publishState(.unavailable)
                return
            }

            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configureSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard let self else { return }
                    if granted {
                        self.configureSession()
                    } else {
                        self.publishState(.denied)
                    }
                }
            case .denied, .restricted:
                publishState(.denied)
            @unknown default:
                publishState(.unavailable)
            }
        }

        func setRunning(_ running: Bool) {
            wantsRunning = running
            sessionQueue.async {
                guard let session = self.session else { return }

                if running {
                    guard self.isConfigured, !session.isRunning else { return }
                    session.startRunning()
                } else if session.isRunning {
                    session.stopRunning()
                }
            }
        }

        private func configureSession() {
            sessionQueue.async {
                guard !self.isConfigured else { return }
                guard let device = AVCaptureDevice.default(for: .video) else {
                    self.publishState(.unavailable)
                    return
                }

                do {
                    let session = AVCaptureSession()
                    let metadataOutput = AVCaptureMetadataOutput()
                    let input = try AVCaptureDeviceInput(device: device)
                    session.beginConfiguration()
                    session.sessionPreset = .high

                    guard session.canAddInput(input), session.canAddOutput(metadataOutput) else {
                        session.commitConfiguration()
                        self.publishState(.unavailable)
                        return
                    }

                    session.addInput(input)
                    session.addOutput(metadataOutput)
                    metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                    metadataOutput.metadataObjectTypes = [
                        .ean8, .ean13, .upce, .code128, .code39, .qr
                    ]
                    session.commitConfiguration()
                    self.session = session
                    self.metadataOutput = metadataOutput
                    self.isConfigured = true

                    Task { @MainActor in
                        self.previewView?.setNeedsLayout()
                        #if !targetEnvironment(simulator)
                        self.previewView?.previewLayer.session = session
                        #endif
                    }

                    self.publishState(.ready)

                    if self.wantsRunning {
                        session.startRunning()
                    }
                } catch {
                    self.publishState(.unavailable)
                }
            }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard
                let code = metadataObjects
                    .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
                    .compactMap(\.stringValue)
                    .first
            else {
                return
            }

            let now = Date()
            guard code != lastCode || now.timeIntervalSince(lastDetection) > 1.2 else { return }
            lastCode = code
            lastDetection = now
            onCodeDetected(code)
        }

        private var isSimulatorEnvironment: Bool {
            #if targetEnvironment(simulator)
            true
            #else
            false
            #endif
        }

        private func publishState(_ state: DecoderStore.CameraState) {
            DispatchQueue.main.async {
                self.onStateChanged(state)
            }
        }
    }
}
