import Foundation

struct ReviewSession {
    var imagePath: String
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
