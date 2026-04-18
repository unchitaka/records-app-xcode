import AVFoundation
import Foundation

protocol CameraService {
    var isSessionRunning: Bool { get }
    func startSession()
    func stopSession()
    func capturePhoto(completion: @escaping (Result<Data, Error>) -> Void)
}

final class AVCameraService: NSObject, CameraService {
    private let logger: AppLogger
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var pendingCompletion: ((Result<Data, Error>) -> Void)?

    init(logger: AppLogger) {
        self.logger = logger
        super.init()
        configureSession()
    }

    var isSessionRunning: Bool { session.isRunning }

    func startSession() {
        guard !session.isRunning else { return }
        session.startRunning()
    }

    func stopSession() {
        guard session.isRunning else { return }
        session.stopRunning()
    }

    func capturePhoto(completion: @escaping (Result<Data, Error>) -> Void) {
        pendingCompletion = completion
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(output)
        else {
            logger.error("Camera session configuration failed")
            return
        }

        session.addInput(input)
        session.addOutput(output)
        session.sessionPreset = .photo
    }
}

extension AVCameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            pendingCompletion?(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            pendingCompletion?(.failure(CameraError.emptyCapture))
            return
        }

        pendingCompletion?(.success(data))
    }
}

enum CameraError: Error {
    case emptyCapture
}
