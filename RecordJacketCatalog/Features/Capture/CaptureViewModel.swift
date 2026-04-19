import AVFoundation
import Foundation
internal import Combine

@MainActor
final class CaptureViewModel: ObservableObject {

    @Published var isBusy = false
    @Published var errorMessage: String?

    let camera: CameraService
    private let ocr: OCRService
    private let logger: AppLogger


    var previewSession: AVCaptureSession? {
        camera.previewSession
    }

    init(camera: CameraService, ocr: OCRService, logger: AppLogger) {
        self.camera = camera
        self.ocr = ocr
        self.logger = logger
    }

    func onAppear() {
        camera.startSession()
    }

    func onDisappear() {
        camera.stopSession()
    }

    func captureAndRunOCR(onComplete: @escaping (ReviewSession) -> Void) {
        isBusy = true
        errorMessage = nil

        camera.capturePhoto { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let data):
                    let path = self.persistCaptureData(data)
                    let ocrResult = await self.ocr.processImageData(data)

                    let session = ReviewSession(
                        imagePath: path,
                        rawOCRText: ocrResult.rawText,
                        fields: ocrResult.extractedFields,
                        glareWarning: ocrResult.glareDetected,
                        lookupHistory: [],
                        candidates: [],
                        selectedCandidateID: nil,
                        unresolved: false,
                        tags: []
                    )

                    self.isBusy = false
                    onComplete(session)

                case .failure(let error):
                    self.logger.error("Capture failed: \(error.localizedDescription)")
                    self.errorMessage = "Capture failed. Please try again."
                    self.isBusy = false
                }
            }
        }
    }

    private func persistCaptureData(_ data: Data) -> String {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let file = dir.appendingPathComponent("capture-\(UUID().uuidString).jpg")

        do {
            try data.write(to: file)
        } catch {
            logger.error("Failed writing image file")
        }

        return file.path
    }
}
