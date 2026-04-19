import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.connection?.videoOrientation = .portrait
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }

        if let connection = uiView.previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}

final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
