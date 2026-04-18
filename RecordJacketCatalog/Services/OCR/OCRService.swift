import Foundation
import ImageIO
import Vision

struct OCRResult {
    let rawText: String
    let extractedFields: EditableFields
    let glareDetected: Bool
}

protocol OCRService {
    func processImageData(_ data: Data) async -> OCRResult
}

final class VisionOCRService: OCRService {
    private let logger: AppLogger

    init(logger: AppLogger) {
        self.logger = logger
    }

    func processImageData(_ data: Data) async -> OCRResult {
        let rawText = await recognizeText(data) ?? ""
        let fields = extractFields(rawText)
        let glare = detectGlare(data)
        logger.info("OCR complete. glareDetected=\(glare)")
        return OCRResult(rawText: rawText, extractedFields: fields, glareDetected: glare)
    }

    private func recognizeText(_ data: Data) async -> String? {
        guard let image = CGImageSourceCreateWithData(data as CFData, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image)
            try? handler.perform([request])
        }
    }

    private func extractFields(_ text: String) -> EditableFields {
        let lines = text.split(separator: "\n").map(String.init)
        let title = lines.first ?? ""
        let artist = lines.dropFirst().first ?? ""
        let catalogRegex = try? NSRegularExpression(pattern: "([A-Z]{1,5}-?\\d{1,5})", options: .caseInsensitive)
        let catalog = catalogRegex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)).flatMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        } ?? ""

        return EditableFields(title: title, artist: artist, catalogNumber: catalog, label: "", year: "")
    }

    private func detectGlare(_ data: Data) -> Bool {
        data.prefix(128).filter { $0 > 245 }.count > 48
    }
}
