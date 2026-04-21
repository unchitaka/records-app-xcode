import Foundation
import ImageIO
import Vision

struct OCRResult {
    let rawText: String
    let boxes: [OCRTextBox]
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
        let boxes = await recognizeTextBoxes(data)
        let rawText = boxes.map(\.text).joined(separator: "\n")
        let fields = extractFields(from: boxes, fallbackRawText: rawText)
        let glare = detectGlare(data)
        logger.info("OCR complete. boxes=\(boxes.count), glareDetected=\(glare)")
        return OCRResult(rawText: rawText, boxes: boxes, extractedFields: fields, glareDetected: glare)
    }

    private func recognizeTextBoxes(_ data: Data) async -> [OCRTextBox] {
        guard let image = CGImageSourceCreateWithData(data as CFData, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let boxes: [OCRTextBox] = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else {
                        return nil
                    }

                    let trimmed = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }

                    return OCRTextBox(
                        text: trimmed,
                        confidence: candidate.confidence,
                        normalizedRect: OCRNormalizedRect(
                            x: observation.boundingBox.origin.x,
                            y: observation.boundingBox.origin.y,
                            width: observation.boundingBox.width,
                            height: observation.boundingBox.height
                        )
                    )
                }

                continuation.resume(returning: boxes.sorted(by: Self.readingOrder))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image)
            try? handler.perform([request])
        }
    }

    private func extractFields(from boxes: [OCRTextBox], fallbackRawText: String) -> EditableFields {
        let text = fallbackRawText
        let lines = boxes.map(\.text)
        let ranked = rankCandidates(from: boxes)

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

        let rankedCatalog = ranked.first(where: { $0.kind == .catalog })?.box.text ?? ""
        let resolvedCatalog = !catalog.isEmpty ? catalog : rankedCatalog
        let rankedTitle = ranked.first(where: { $0.kind == .title && !$0.box.text.isEmpty })?.box.text ?? ""
        let rankedArtist = ranked.first(where: { $0.kind == .artist && !$0.box.text.isEmpty })?.box.text ?? ""
        let title = !rankedTitle.isEmpty ? rankedTitle : (nonCatalogLines.first ?? lines.first ?? "")
        let artist = !rankedArtist.isEmpty
            ? rankedArtist
            : (nonCatalogLines.dropFirst().first ?? lines.dropFirst().first ?? "")
        let year = detectYear(in: text)

        return EditableFields(title: title, artist: artist, catalogNumber: resolvedCatalog, label: "", year: year)
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

    private static func readingOrder(lhs: OCRTextBox, rhs: OCRTextBox) -> Bool {
        let leftY = lhs.normalizedRect.y
        let rightY = rhs.normalizedRect.y
        if abs(leftY - rightY) > 0.02 {
            return leftY > rightY
        }
        return lhs.normalizedRect.x < rhs.normalizedRect.x
    }

    private enum RankedKind {
        case catalog
        case title
        case artist
    }

    private struct RankedBox {
        let box: OCRTextBox
        let score: Double
        let kind: RankedKind
    }

    private func rankCandidates(from boxes: [OCRTextBox]) -> [RankedBox] {
        boxes.enumerated()
            .map { index, box in
                let text = box.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasDigits = text.rangeOfCharacter(from: .decimalDigits) != nil
                let containsJapanese = text.unicodeScalars.contains { scalar in
                    switch scalar.value {
                    case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF:
                        return true
                    default:
                        return false
                    }
                }

                var catalogScore = hasDigits ? 40.0 : 0.0
                if hasDigits && text.range(of: #"[A-Za-z]{1,6}[\-\s]?[A-Za-z0-9]{1,10}[\-\s]?[0-9]{1,6}"#, options: .regularExpression) != nil {
                    catalogScore += 15
                }

                var titleScore = containsJapanese ? 24.0 : 8.0
                var artistScore = containsJapanese ? 22.0 : 8.0
                if (4...36).contains(text.count) {
                    titleScore += 6
                    artistScore += 8
                }
                if text.contains("・") || text.contains("&") || text.contains("/") {
                    artistScore += 6
                }

                let likelyKind: RankedKind = {
                    if catalogScore >= max(titleScore, artistScore) { return .catalog }
                    if artistScore >= titleScore { return .artist }
                    return .title
                }()

                var score = Double(box.confidence) * 10
                score += max(catalogScore, titleScore, artistScore)
                if text.count <= 2 { score -= 15 }
                if text.range(of: #"^[\p{P}\p{S}\s]+$"#, options: .regularExpression) != nil {
                    score -= 30
                }

                score -= Double(index) * 0.01
                return RankedBox(box: box, score: score, kind: likelyKind)
            }
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.0001 {
                    return lhs.score > rhs.score
                }
                return Self.readingOrder(lhs: lhs.box, rhs: rhs.box)
            }
    }
}
