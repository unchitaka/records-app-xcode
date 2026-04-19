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
        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let catalogPatterns = [
            #"\b([A-Z]{1,6}[\-\s]?[A-Z0-9]{1,8}[\-\s]?[0-9]{1,6})\b"#,
            #"\b([A-Z]{1,4}\s?\d{2,6})\b"#
        ]

        let catalog = catalogPatterns.lazy.compactMap { pattern -> String? in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let captureRange = Range(match.range(at: 1), in: text)
            else {
                return nil
            }
            return String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }.first ?? ""

        let nonCatalogLines = lines.filter { line in
            catalog.isEmpty || !line.localizedCaseInsensitiveContains(catalog)
        }

        let title = nonCatalogLines.first ?? lines.first ?? ""
        let artist = inferArtistLine(
            from: Array(nonCatalogLines.dropFirst()),
            fallback: Array(lines.dropFirst())
        )
        let year = detectYear(in: text)

        return EditableFields(title: title, artist: artist, catalogNumber: catalog, label: "", year: year)
    }

    private func inferArtistLine(from primary: [String], fallback: [String]) -> String {
        let likelyArtist = primary.first(where: {
            let lowered = $0.lowercased()
            return lowered.contains(" - ")
                || lowered.contains("feat")
                || lowered.contains("featuring")
                || lowered.contains("&")
        })

        if let likelyArtist {
            return likelyArtist
        }

        return primary.first ?? fallback.first ?? ""
    }

    private func detectYear(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b(19\d{2}|20\d{2})\b"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else {
            return ""
        }
        return String(text[range])
    }

    private func detectGlare(_ data: Data) -> Bool {
        data.prefix(128).filter { $0 > 245 }.count > 48
    }
}
