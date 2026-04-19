import Foundation

enum OCRImageInputSource: String, Codable {
    case correctedCrop
    case originalFallback
    case unknown
}

struct ReviewSession {
    var imagePath: String
    var correctedCropPath: String?
    var ocrInputSource: OCRImageInputSource
    var rawOCRText: String
    var fields: EditableFields
    var glareWarning: Bool
    var lookupHistory: [LookupQueryLog]
    var candidates: [DiscogsCandidate]
    var selectedCandidateID: Int?
    var unresolved: Bool
    var tags: [String]

    static func empty(imagePath: String) -> ReviewSession {
        .init(
            imagePath: imagePath,
            correctedCropPath: nil,
            ocrInputSource: .unknown,
            rawOCRText: "",
            fields: .empty,
            glareWarning: false,
            lookupHistory: [],
            candidates: [],
            selectedCandidateID: nil,
            unresolved: false,
            tags: []
        )
    }
}

extension ReviewSession {
    init(record: RecordItem) {
        self.init(
            imagePath: record.imagePath,
            correctedCropPath: record.correctedCropPath,
            ocrInputSource: record.correctedCropPath == nil ? .originalFallback : .correctedCrop,
            rawOCRText: record.rawOCRText,
            fields: record.editableFields,
            glareWarning: false,
            lookupHistory: record.queryHistory,
            candidates: record.latestCandidates,
            selectedCandidateID: record.selectedDiscogsMatch?.id,
            unresolved: record.unresolved,
            tags: record.tags
        )
    }
}
