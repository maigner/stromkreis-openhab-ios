// Copyright (c) 2026 Stromkreis contributors
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0
//
// SPDX-License-Identifier: EPL-2.0

import AVFoundation
import SwiftUI
import UIKit

/// Live camera preview that reports the first QR code it recognizes.
struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    var onUnavailable: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCode = onCode
        controller.onUnavailable = onUnavailable
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
        uiViewController.onCode = onCode
        uiViewController.onUnavailable = onUnavailable
    }
}

final class QRScannerViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onUnavailable: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "net.stromkreis.app.qrscanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var configured = false
    private var delivered = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        delivered = false
        requestAccessAndStart()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        if let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = rotationAngle()
        }
    }

    private func rotationAngle() -> CGFloat {
        switch view.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: 180
        case .landscapeRight: 0
        case .portraitUpsideDown: 270
        default: 90
        }
    }

    private func requestAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureAndStart()
                    } else {
                        self?.onUnavailable?(String(localized: "Camera access was denied. Allow it in Settings or paste the setup link below."))
                    }
                }
            }
        default:
            onUnavailable?(String(localized: "Camera access was denied. Allow it in Settings or paste the setup link below."))
        }
    }

    private func configureAndStart() {
        if !configured {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                onUnavailable?(String(localized: "No camera available on this device. Paste the setup link below instead."))
                return
            }
            session.beginConfiguration()
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                onUnavailable?(String(localized: "No camera available on this device. Paste the setup link below instead."))
                return
            }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                onUnavailable?(String(localized: "No camera available on this device. Paste the setup link below instead."))
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            session.commitConfiguration()

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            previewLayer = layer
            configured = true
        }
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !delivered,
              let object = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first(where: { $0.type == .qr }),
              let value = object.stringValue, !value.isEmpty else { return }
        delivered = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        onCode?(value)
    }
}
