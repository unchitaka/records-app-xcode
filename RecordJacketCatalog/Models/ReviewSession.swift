import Foundation

enum OCRImageInputSource: String, Codable {
    case correctedCrop
    case originalFallback
    case unknown
}

enum OCRSelectionMode: String, CaseIterable, Codable {
    case title = "Select Title"
    case artist = "Select Artist"
    case catalog = "Select Catalog"
}

struct ReviewSession {
    var imagePath: String
    var correctedCropPath: String?
    var ocrInputSource: OCRImageInputSource
    var rawOCRText: String
    var ocrBoxes: [OCRTextBox]
    var selectedTitleBoxIDs: [UUID]
    var selectedArtistBoxIDs: [UUID]
    var selectedCatalogBoxIDs: [UUID]
    var fields: EditableFields
    var glareWarning: Bool
    var lookupHistory: [LookupQueryLog]
    var candidates: [DiscogsCandidate]
    var selectedCandidateID: Int?
    var selectedDiscogsMatch: DiscogsCandidate?
    var confirmedDiscogsSummary: DiscogsReleaseSummary?
    var confirmedDiscogsRelease: DiscogsReleaseDetails?
    var unresolved: Bool
    var tags: [String]

    static func empty(imagePath: String) -> ReviewSession {
        .init(
            imagePath: imagePath,
            correctedCropPath: nil,
            ocrInputSource: .unknown,
            rawOCRText: "",
            ocrBoxes: [],
            selectedTitleBoxIDs: [],
            selectedArtistBoxIDs: [],
            selectedCatalogBoxIDs: [],
            fields: .empty,
            glareWarning: false,
            lookupHistory: [],
            candidates: [],
            selectedCandidateID: nil,
            selectedDiscogsMatch: nil,
            confirmedDiscogsSummary: nil,
            confirmedDiscogsRelease: nil,
            unresolved: false,
            tags: []
        )
    }
}

extension ReviewSession {
    var preferredImagePath: String {
        let cropped = correctedCropPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cropped.isEmpty ? imagePath : cropped
    }

    init(record: RecordItem) {
        self.init(
            imagePath: record.imagePath,
            correctedCropPath: record.correctedCropPath,
            ocrInputSource: record.correctedCropPath == nil ? .originalFallback : .correctedCrop,
            rawOCRText: record.rawOCRText,
            ocrBoxes: record.ocrBoxes,
            selectedTitleBoxIDs: record.selectedTitleBoxIDs,
            selectedArtistBoxIDs: record.selectedArtistBoxIDs,
            selectedCatalogBoxIDs: record.selectedCatalogBoxIDs,
            fields: record.editableFields,
            glareWarning: false,
            lookupHistory: record.queryHistory,
            candidates: record.latestCandidates,
            selectedCandidateID: record.selectedDiscogsMatch?.id,
            selectedDiscogsMatch: record.selectedDiscogsMatch,
            confirmedDiscogsSummary: record.confirmedDiscogsSummary,
            confirmedDiscogsRelease: record.confirmedDiscogsRelease,
            unresolved: record.unresolved,
            tags: record.tags
        )
    }
}
