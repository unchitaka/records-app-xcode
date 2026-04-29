import CoreGraphics
import Foundation

struct EditableFields: Codable, Equatable {
    var title: String
    var artist: String
    var catalogNumber: String
    var label: String
    var year: String

    static let empty = EditableFields(title: "", artist: "", catalogNumber: "", label: "", year: "")
}

struct OCRTextBox: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    var confidence: Float
    var normalizedRect: OCRNormalizedRect

    init(id: UUID = UUID(), text: String, confidence: Float, normalizedRect: OCRNormalizedRect) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.normalizedRect = normalizedRect
    }
}

struct OCRNormalizedRect: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct DiscogsCandidate: Codable, Equatable, Identifiable {
    let id: Int
    var title: String
    var artist: String?
    var catalogNumber: String?
    var year: String?
    var country: String?
    var format: String?
    var resourceURL: String?
    var thumb: String?
    var uri: String?
}

struct DiscogsReleaseSummary: Codable, Equatable {
    let id: Int
    var title: String
    var artist: String?
    var catalogNumber: String?
    var year: String?
    var country: String?
    var format: String?
    var resourceURL: String?
    var thumb: String?
    var uri: String?

    init(candidate: DiscogsCandidate) {
        id = candidate.id
        title = candidate.title
        artist = candidate.artist
        catalogNumber = candidate.catalogNumber
        year = candidate.year
        country = candidate.country
        format = candidate.format
        resourceURL = candidate.resourceURL
        thumb = candidate.thumb
        uri = candidate.uri
    }
}

struct DiscogsReleaseDetails: Codable, Equatable {
    struct Artist: Codable, Equatable, Identifiable {
        let id: Int?
        var name: String
        var anv: String?
        var join: String?
        var role: String?
        var tracks: String?
    }

    struct Label: Codable, Equatable, Identifiable {
        let id: Int?
        var name: String
        var catalogNumber: String?
    }

    struct Format: Codable, Equatable, Identifiable {
        var id: String { name + descriptions.joined(separator: ",") }
        var name: String
        var qty: String?
        var descriptions: [String]
    }

    struct ImageInfo: Codable, Equatable, Identifiable {
        var id: String { uri ?? uri150 ?? resourceURL ?? "\(type ?? "unknown")-\(width ?? 0)x\(height ?? 0)" }
        var type: String?
        var uri: String?
        var uri150: String?
        var width: Int?
        var height: Int?
        var resourceURL: String?
    }

    let id: Int
    var title: String
    var year: Int?
    var country: String?
    var formats: [Format]
    var labels: [Label]
    var catalogNumbers: [String]
    var artists: [Artist]
    var genres: [String]
    var styles: [String]
    var notes: String?
    var thumb: String?
    var images: [ImageInfo]
    var uri: String?
    var resourceURL: String?
    var status: String?
    var masterID: Int?
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
    var ocrBoxes: [OCRTextBox]
    var selectedTitleBoxIDs: [UUID]
    var selectedArtistBoxIDs: [UUID]
    var selectedCatalogBoxIDs: [UUID]
    var editableFields: EditableFields
    var artistIndex: String
    var queryHistory: [LookupQueryLog]
    var latestCandidates: [DiscogsCandidate]
    var selectedDiscogsMatch: DiscogsCandidate?
    var confirmedDiscogsSummary: DiscogsReleaseSummary?
    var confirmedDiscogsRelease: DiscogsReleaseDetails?
    var unresolved: Bool
    var tags: [String]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        imagePath: String,
        correctedCropPath: String? = nil,
        rawOCRText: String,
        ocrBoxes: [OCRTextBox] = [],
        selectedTitleBoxIDs: [UUID] = [],
        selectedArtistBoxIDs: [UUID] = [],
        selectedCatalogBoxIDs: [UUID] = [],
        editableFields: EditableFields,
        artistIndex: String? = nil,
        queryHistory: [LookupQueryLog] = [],
        latestCandidates: [DiscogsCandidate] = [],
        selectedDiscogsMatch: DiscogsCandidate? = nil,
        confirmedDiscogsSummary: DiscogsReleaseSummary? = nil,
        confirmedDiscogsRelease: DiscogsReleaseDetails? = nil,
        unresolved: Bool,
        tags: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imagePath = imagePath
        self.correctedCropPath = correctedCropPath
        self.rawOCRText = rawOCRText
        self.ocrBoxes = ocrBoxes
        self.selectedTitleBoxIDs = selectedTitleBoxIDs
        self.selectedArtistBoxIDs = selectedArtistBoxIDs
        self.selectedCatalogBoxIDs = selectedCatalogBoxIDs
        self.editableFields = editableFields
        self.artistIndex = RecordItem.normalizedArtistIndex(
            artistIndex ?? editableFields.artist,
            fallbackArtist: selectedDiscogsMatch?.artist ?? confirmedDiscogsSummary?.artist
        )
        self.queryHistory = queryHistory
        self.latestCandidates = latestCandidates
        self.selectedDiscogsMatch = selectedDiscogsMatch
        self.confirmedDiscogsSummary = confirmedDiscogsSummary
        self.confirmedDiscogsRelease = confirmedDiscogsRelease
        self.unresolved = unresolved
        self.tags = tags
    }

    static func normalizedArtistIndex(_ value: String, fallbackArtist: String? = nil) -> String {
        let preferred = value.trimmedIfNotEmpty ?? fallbackArtist?.trimmedIfNotEmpty ?? "Unknown Artist"
        let folded = preferred.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let collapsed = folded.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "unknown artist" : collapsed
    }
}

private extension String {
    var trimmedIfNotEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension RecordItem {
    var preferredImagePath: String {
        validPreferredImagePath ?? imagePath
    }

    var validPreferredImagePath: String? {
        candidateImagePaths.first
    }

    var candidateImagePaths: [String] {
        Self.resolvedExistingImagePaths(correctedCropPath: correctedCropPath, imagePath: imagePath)
    }

    static func resolvedExistingImagePaths(correctedCropPath: String?, imagePath: String) -> [String] {
        let candidates = [correctedCropPath, imagePath]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var resolved: [String] = []
        for candidate in candidates {
            if let existing = resolveExistingPath(candidate), !resolved.contains(existing) {
                resolved.append(existing)
            }
        }
        return resolved
    }

    private static func resolveExistingPath(_ candidate: String) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: candidate) {
            return candidate
        }

        let fileName = URL(fileURLWithPath: candidate).lastPathComponent
        guard !fileName.isEmpty else { return nil }
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let docs else { return nil }
        let relativePath = docs.appendingPathComponent(fileName).path
        return fm.fileExists(atPath: relativePath) ? relativePath : nil
    }
}
