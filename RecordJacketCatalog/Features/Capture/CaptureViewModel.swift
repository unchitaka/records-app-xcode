import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import Vision
internal import Combine

@MainActor
final class CaptureViewModel: ObservableObject {

    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var selectedFixtureIndex: Int

    let camera: CameraService
    private let ocr: OCRService
    private let logger: AppLogger
    private let cropProcessor: CoverCropProcessor

    var previewSession: AVCaptureSession? {
        camera.previewSession
    }

    init(camera: CameraService, ocr: OCRService, logger: AppLogger) {
        self.camera = camera
        self.ocr = ocr
        self.logger = logger
        self.cropProcessor = VisionCoverCropProcessor(logger: logger)
        self.selectedFixtureIndex = camera.selectedFixtureIndex
    }

    func onAppear() {
        camera.startSession()
    }

    func onDisappear() {
        camera.stopSession()
    }

    var fixtureNames: [String] {
        camera.fixtureNames
    }

    var selectedFixtureImage: UIImage? {
        guard let data = camera.selectedFixtureImageData else { return nil }
        return UIImage(data: data)
    }

    var selectedFixtureName: String? {
        camera.selectedFixtureName
    }

    func selectFixture(at index: Int) {
        camera.selectFixture(at: index)
        selectedFixtureIndex = camera.selectedFixtureIndex
    }

    func captureAndRunOCR(onComplete: @escaping (ReviewSession) -> Void) {
        isBusy = true
        errorMessage = nil

        camera.capturePhoto { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let data):
                    let normalizedCaptureData = ImageOrientationNormalizer.normalizedJPEGData(from: data) ?? data
                    let originalPath = self.persistCaptureData(normalizedCaptureData, prefix: "capture")
                    let cropResult = self.cropProcessor.generateCorrectedCover(from: normalizedCaptureData)
                    let normalizedCorrectedData = cropResult.data.map { ImageOrientationNormalizer.normalizedJPEGData(from: $0) ?? $0 }
                    let ocrData = normalizedCorrectedData ?? normalizedCaptureData
                    let ocrSource: OCRImageInputSource = cropResult.data != nil ? .correctedCrop : .originalFallback

                    let correctedPath: String?
                    if let correctedData = normalizedCorrectedData {
                        correctedPath = self.persistCaptureData(correctedData, prefix: "corrected")
                    } else {
                        correctedPath = nil
                    }

                    self.logger.info("OCR input source=\(ocrSource.rawValue), hasCrop=\(correctedPath != nil)")
                    let ocrResult = await self.ocr.processImageData(ocrData)

                    let session = ReviewSession(
                        id: UUID(),
                        imagePath: originalPath,
                        correctedCropPath: correctedPath,
                        ocrInputSource: ocrSource,
                        rawOCRText: ocrResult.rawText,
                        ocrBoxes: ocrResult.boxes,
                        selectedTitleBoxIDs: [],
                        selectedArtistBoxIDs: [],
                        selectedCatalogBoxIDs: [],
                        fields: self.camera.selectedFixtureFields ?? ocrResult.extractedFields,
                        glareWarning: ocrResult.glareDetected,
                        lookupHistory: [],
                        candidates: [],
                        selectedCandidateID: nil,
                        selectedDiscogsMatch: nil,
                        confirmedDiscogsSummary: nil,
                        confirmedDiscogsRelease: nil,
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

    private func persistCaptureData(_ data: Data, prefix: String) -> String {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let file = dir.appendingPathComponent("\(prefix)-\(UUID().uuidString).jpg")

        do {
            try data.write(to: file)
        } catch {
            logger.error("Failed writing image file")
        }

        return file.path
    }
}

private enum ImageOrientationNormalizer {
    static func normalizedJPEGData(from data: Data, compressionQuality: CGFloat = 0.92) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        if image.imageOrientation == .up {
            return image.jpegData(compressionQuality: compressionQuality) ?? data
        }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: image.size))
        guard let normalizedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            return image.jpegData(compressionQuality: compressionQuality) ?? data
        }
        return normalizedImage.jpegData(compressionQuality: compressionQuality)
    }
}

private protocol CoverCropProcessor {
    func generateCorrectedCover(from imageData: Data) -> CoverCropResult
}

private struct CoverCropResult {
    let data: Data?
}

private final class VisionCoverCropProcessor: CoverCropProcessor {
    private let logger: AppLogger
    private let ciContext = CIContext(options: nil)

    init(logger: AppLogger) {
        self.logger = logger
    }

    func generateCorrectedCover(from imageData: Data) -> CoverCropResult {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            logger.error("Cover crop: unable to read captured image data")
            return CoverCropResult(data: nil)
        }

        guard let rectangle = detectRectangle(in: cgImage) else {
            logger.info("Cover crop: no rectangle detected, using original image")
            return CoverCropResult(data: nil)
        }

        guard let corrected = perspectiveCorrect(cgImage: cgImage, rectangle: rectangle) else {
            logger.error("Cover crop: perspective correction failed, using original image")
            return CoverCropResult(data: nil)
        }

        guard let encoded = encodeJPEG(corrected) else {
            logger.error("Cover crop: failed encoding corrected crop, using original image")
            return CoverCropResult(data: nil)
        }

        logger.info("Cover crop: rectangle detected and corrected")
        return CoverCropResult(data: encoded)
    }

    private func detectRectangle(in cgImage: CGImage) -> VNRectangleObservation? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = 0.5
        request.minimumAspectRatio = 0.7
        request.quadratureTolerance = 20

        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
        } catch {
            logger.error("Cover crop rectangle detection failed: \(error.localizedDescription)")
            return nil
        }

        return (request.results ?? []).first
    }

    private func perspectiveCorrect(cgImage: CGImage, rectangle: VNRectangleObservation) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        let topLeft = CGPoint(x: rectangle.topLeft.x * width, y: rectangle.topLeft.y * height)
        let topRight = CGPoint(x: rectangle.topRight.x * width, y: rectangle.topRight.y * height)
        let bottomLeft = CGPoint(x: rectangle.bottomLeft.x * width, y: rectangle.bottomLeft.y * height)
        let bottomRight = CGPoint(x: rectangle.bottomRight.x * width, y: rectangle.bottomRight.y * height)

        let corrected = ciImage.applyingFilter(
            "CIPerspectiveCorrection",
            parameters: [
                "inputTopLeft": CIVector(cgPoint: topLeft),
                "inputTopRight": CIVector(cgPoint: topRight),
                "inputBottomLeft": CIVector(cgPoint: bottomLeft),
                "inputBottomRight": CIVector(cgPoint: bottomRight)
            ]
        )

        return ciContext.createCGImage(corrected, from: corrected.extent)
    }

    private func encodeJPEG(_ image: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
