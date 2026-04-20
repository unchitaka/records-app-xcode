import AVFoundation
import Foundation

protocol CameraService {
    var isSessionRunning: Bool { get }
    var previewSession: AVCaptureSession? { get }
    func startSession()
    func stopSession()
    func capturePhoto(completion: @escaping (Result<Data, Error>) -> Void)
}

final class AVCameraService: NSObject, CameraService {
    private let logger: AppLogger
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    private var pendingCompletion: ((Result<Data, Error>) -> Void)?
    private var isConfigured = false

    init(logger: AppLogger) {
        self.logger = logger
        super.init()

        sessionQueue.sync {
            self.configureSession()
        }
    }

    var isSessionRunning: Bool { session.isRunning }
    var previewSession: AVCaptureSession? { isConfigured ? session : nil }

    func startSession() {
        sessionQueue.async {
            guard self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stopSession() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capturePhoto(completion: @escaping (Result<Data, Error>) -> Void) {
        sessionQueue.async {
            guard self.isConfigured else {
                completion(.failure(CameraError.notConfigured))
                return
            }

            guard self.pendingCompletion == nil else {
                completion(.failure(CameraError.captureInProgress))
                return
            }

            self.pendingCompletion = completion

            let settings = AVCapturePhotoSettings()
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            logger.error("No back camera available")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)

            guard session.canAddInput(input) else {
                logger.error("Cannot add camera input")
                return
            }

            guard session.canAddOutput(output) else {
                logger.error("Cannot add photo output")
                return
            }

            session.addInput(input)
            session.addOutput(output)
            isConfigured = true

        } catch {
            logger.error("Camera session configuration failed: \(error.localizedDescription)")
        }
    }
}

@preconcurrency
extension AVCameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let completion = pendingCompletion
        pendingCompletion = nil

        if let error {
            completion?(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            completion?(.failure(CameraError.emptyCapture))
            return
        }

        completion?(.success(data))
    }
}

enum CameraError: Error {
    case emptyCapture
    case notConfigured
    case captureInProgress
}
