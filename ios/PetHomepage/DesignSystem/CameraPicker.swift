// ios/PetHomepage/DesignSystem/CameraPicker.swift
import AVFoundation
import SwiftUI
import UIKit

/// SwiftUI wrapper over a custom AVFoundation camera. Replaces the earlier
/// UIImagePickerController wrapper because the system camera sheet cannot zoom — its
/// preview-transform hack never affects the captured image. Present as `.fullScreenCover`
/// (the camera needs the full screen; a nested `.sheet` collapses immediately). Dismissal is
/// explicit via `onFinish`, which the caller wires to flip the presenting binding.
struct CameraPicker: UIViewControllerRepresentable {
    /// Whether the device actually has a camera (false on Simulator). Callers gate on this.
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    let onCapture: (UIImage) -> Void
    /// Called after the user captures or cancels — the caller dismisses the presentation here.
    let onFinish: () -> Void
    /// Optional "choose from library instead" shortcut inside the camera UI. The caller
    /// dismisses the camera and presents its photo picker (pending-flag/onDismiss pattern).
    var onPickLibrary: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> ZoomableCameraViewController {
        let controller = ZoomableCameraViewController()
        controller.onCapture = onCapture
        controller.onFinish = onFinish
        controller.onPickLibrary = onPickLibrary
        return controller
    }

    func updateUIViewController(_ uiViewController: ZoomableCameraViewController, context: Context) {}
}

/// Minimal portrait camera: pinch-to-zoom (real sensor zoom via videoZoomFactor, not a
/// preview transform), shutter, cancel, optional library shortcut, and a live zoom badge.
final class ZoomableCameraViewController: UIViewController {
    var onCapture: ((UIImage) -> Void)?
    var onFinish: (() -> Void)?
    var onPickLibrary: (() -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "pet.homepage.camera.session")
    private var device: AVCaptureDevice?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var pinchStartZoom: CGFloat = 1

    private let zoomLabel = UILabel()
    private let deniedLabel = UILabel()

    /// Zoom ceiling: generous for pets across the park, but short of the digital-mush range.
    private let maxZoomCap: CGFloat = 10

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        buildControls()
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self,
                                                           action: #selector(handlePinch(_:))))

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.configureAndStart() : self?.showDenied()
                }
            }
        default:
            showDenied()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - Session

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            if let camera = AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: camera),
               self.session.canAddInput(input) {
                self.session.addInput(input)
                self.device = camera
            }
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            // Portrait-only app: pin the capture orientation to match.
            if let connection = self.photoOutput.connection(with: .video),
               connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    private func showDenied() {
        deniedLabel.isHidden = false
    }

    // MARK: - Controls

    private func buildControls() {
        // Shutter: white ring, centered at the bottom.
        let shutter = UIButton(type: .custom)
        shutter.translatesAutoresizingMaskIntoConstraints = false
        shutter.layer.cornerRadius = 34
        shutter.layer.borderWidth = 5
        shutter.layer.borderColor = UIColor.white.cgColor
        shutter.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        shutter.accessibilityLabel = "Take photo"
        shutter.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)

        let cancel = symbolButton("xmark", label: "Cancel", action: #selector(cancelTapped))
        let library = symbolButton("photo.on.rectangle", label: "Choose from library",
                                   action: #selector(libraryTapped))
        library.isHidden = (onPickLibrary == nil)

        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        zoomLabel.text = "1.0×"
        zoomLabel.textColor = .white
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        zoomLabel.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        zoomLabel.layer.cornerRadius = 12
        zoomLabel.layer.masksToBounds = true
        zoomLabel.textAlignment = .center

        deniedLabel.translatesAutoresizingMaskIntoConstraints = false
        deniedLabel.text = "Camera access is off.\nEnable it in Settings → Privacy → Camera."
        deniedLabel.textColor = .white
        deniedLabel.numberOfLines = 0
        deniedLabel.textAlignment = .center
        deniedLabel.font = .preferredFont(forTextStyle: .callout)
        deniedLabel.isHidden = true

        [shutter, cancel, library, zoomLabel, deniedLabel].forEach(view.addSubview)

        NSLayoutConstraint.activate([
            shutter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                            constant: -28),
            shutter.widthAnchor.constraint(equalToConstant: 68),
            shutter.heightAnchor.constraint(equalToConstant: 68),

            cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cancel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            library.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            library.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),

            zoomLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoomLabel.bottomAnchor.constraint(equalTo: shutter.topAnchor, constant: -18),
            zoomLabel.widthAnchor.constraint(equalToConstant: 56),
            zoomLabel.heightAnchor.constraint(equalToConstant: 24),

            deniedLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            deniedLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            deniedLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            deniedLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func symbolButton(_ systemName: String, label: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // MARK: - Actions

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let device else { return }
        if gesture.state == .began { pinchStartZoom = device.videoZoomFactor }
        let ceiling = min(device.activeFormat.videoMaxZoomFactor, maxZoomCap)
        let target = max(1, min(pinchStartZoom * gesture.scale, ceiling))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = target
            device.unlockForConfiguration()
            zoomLabel.text = String(format: "%.1f×", target)
        } catch {
            // Zoom is cosmetic; a lock failure just leaves the current factor.
        }
    }

    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func cancelTapped() { onFinish?() }

    @objc private func libraryTapped() { onPickLibrary?() }
}

extension ZoomableCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if error == nil, let data = photo.fileDataRepresentation(),
           let image = UIImage(data: data) {
            onCapture?(image)
        }
        onFinish?()
    }
}
