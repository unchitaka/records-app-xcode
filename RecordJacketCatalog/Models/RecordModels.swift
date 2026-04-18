import Foundation

struct EditableFields: Codable, Equatable {
    var title: String
    var artist: String
    var catalogNumber: String
    var label: String
    var year: String

    static let empty = EditableFields(title: "", artist: "", catalogNumber: "", label: "", year: "")
}

struct DiscogsCandidate: Codable, Equatable, Identifiable {
    let id: Int
    var title: String
    var year: String?
    var country: String?
    var format: String?
    var resourceURL: String?
}

struct LookupQueryLog: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let query: String

    init(id: UUID = UUID(), timestamp: Date = Date(), query: String) {
        self.id = id
        self.timestamp = timestamp
        self.query = query
    }
}

struct RecordItem: Codable, Equatable, Identifiable {
    let id: UUID
    var createdAt: Date
    var updatedAt: Date
    var imagePath: String
    var correctedCropPath: String?
    var rawOCRText: String
    var editableFields: EditableFields
    var queryHistory: [LookupQueryLog]
    var latestCandidates: [DiscogsCandidate]
    var selectedDiscogsMatch: DiscogsCandidate?
    var unresolved: Bool
    var tags: [String]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        imagePath: String,
        correctedCropPath: String? = nil,
        rawOCRText: String,
        editableFields: EditableFields,
        queryHistory: [LookupQueryLog] = [],
        latestCandidates: [DiscogsCandidate] = [],
        selectedDiscogsMatch: DiscogsCandidate? = nil,
        unresolved: Bool,
        tags: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imagePath = imagePath
        self.correctedCropPath = correctedCropPath
        self.rawOCRText = rawOCRText
        self.editableFields = editableFields
        self.queryHistory = queryHistory
        self.latestCandidates = latestCandidates
        self.selectedDiscogsMatch = selectedDiscogsMatch
        self.unresolved = unresolved
        self.tags = tags
    }
}
