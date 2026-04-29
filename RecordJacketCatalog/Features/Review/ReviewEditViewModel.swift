import Foundation
internal import Combine

@MainActor
final class ReviewEditViewModel: ObservableObject {

    @Published var session: ReviewSession
    @Published var isLookingUp = false
    @Published var isConfirmingCandidate = false
    @Published var lookupError: String?
    @Published var saveMessage: String?
    @Published var stage: EditStage = .basic
    @Published var selectionMode: OCRSelectionMode = .title

    private let repository: RecordRepository
    private let discogs: DiscogsLookupService
    private let coverMatcher: CoverImageMatchService
    private var hasUserModifiedTitle = false
    private var hasUserModifiedArtist = false
    private var hasUserModifiedCatalog = false

    init(
        session: ReviewSession,
        repository: RecordRepository,
        discogs: DiscogsLookupService,
        coverMatcher: CoverImageMatchService
    ) {
        self.session = session
        self.repository = repository
        self.discogs = discogs
        self.coverMatcher = coverMatcher
        applyInitialBestSelectionsIfNeeded()
    }

    enum EditStage: String, CaseIterable {
        case basic = "Basic"
        case advanced = "Advanced"
        case lookup = "Lookup"
    }

    enum OCRSelectionState {
        case selectedInCurrentMode
        case selectedInOtherMode
        case unselected
    }

    enum OCRLikelyType: String {
        case catalog = "Likely catalog"
        case title = "Likely title"
        case artist = "Likely artist"
        case unknown = ""
    }

    struct RankedOCRCandidate: Identifiable {
        let box: OCRTextBox
        let score: Double
        let likelyType: OCRLikelyType
        let hint: String?

        var id: UUID { box.id }
    }

    var selectedCandidate: DiscogsCandidate? {
        guard let selectedID = session.selectedCandidateID else { return nil }
        return session.candidates.first { $0.id == selectedID }
    }

    var trimmedArtist: String {
        session.fields.artist.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool {
        !trimmedArtist.isEmpty
    }

    var artistValidationMessage: String? {
        canSave ? nil : "Artist is required before final save."
    }

    var rankedOCRCandidates: [RankedOCRCandidate] {
        session.ocrBoxes
            .enumerated()
            .map { index, box in
                let rank = Self.rank(box: box, originalIndex: index)
                return RankedOCRCandidate(
                    box: box,
                    score: rank.score,
                    likelyType: rank.likelyType,
                    hint: rank.hint
                )
            }
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.0001 {
                    return lhs.score > rhs.score
                }
                return readingOrderBox(lhs.box, rhs.box)
            }
    }

    func runLookup() async {
        isLookingUp = true
        lookupError = nil
        let query = [session.fields.artist, session.fields.title, session.fields.catalogNumber]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")

        session.lookupHistory.append(LookupQueryLog(query: query))

        do {
            let candidates = try await discogs.searchCandidates(fields: session.fields)
            session.candidates = Array(candidates.prefix(3))
            session.selectedCandidateID = nil
            session.selectedDiscogsMatch = nil
            session.confirmedDiscogsSummary = nil
            session.confirmedDiscogsRelease = nil
        } catch let error as DiscogsLookupError {
            session.candidates = []
            lookupError = error.errorDescription
            await tryCoverMatcherFallbackIfAvailable()
        } catch {
            session.candidates = []
            lookupError = "Unexpected lookup error. Please retry."
            await tryCoverMatcherFallbackIfAvailable()
        }

        isLookingUp = false
    }

    private func tryCoverMatcherFallbackIfAvailable() async {
        guard
            let correctedCropPath = session.correctedCropPath,
            let imageData = try? Data(contentsOf: URL(fileURLWithPath: correctedCropPath))
        else {
            return
        }

        if let candidate = await coverMatcher.findCandidate(using: imageData, fields: session.fields) {
            session.candidates = [candidate]
            lookupError = nil
        }
    }

    func selectCandidate(_ candidate: DiscogsCandidate) {
        session.selectedCandidateID = candidate.id
    }

    func confirmSelectedCandidate() async {
        guard let candidate = selectedCandidate else { return }
        await confirmCandidate(candidate)
    }

    private func confirmCandidate(_ candidate: DiscogsCandidate) async {
        isConfirmingCandidate = true
        lookupError = nil

        do {
            let release = try await discogs.fetchReleaseDetails(for: candidate)
            session.selectedCandidateID = candidate.id
            session.unresolved = false
            session.selectedDiscogsMatch = candidate
            session.confirmedDiscogsSummary = DiscogsReleaseSummary(candidate: candidate)
            session.confirmedDiscogsRelease = release
        } catch let error as DiscogsLookupError {
            lookupError = error.errorDescription
        } catch {
            lookupError = "Unexpected error while confirming release. Please retry."
        }

        isConfirmingCandidate = false
    }

    func markUnresolved() {
        session.selectedCandidateID = nil
        session.unresolved = true
        session.selectedDiscogsMatch = nil
        session.confirmedDiscogsSummary = nil
        session.confirmedDiscogsRelease = nil
    }

    func saveAsUnresolved() {
        markUnresolved()
        save()
    }

    func toggleSelection(for box: OCRTextBox) {
        switch selectionMode {
        case .title:
            hasUserModifiedTitle = true
            toggleID(box.id, in: &session.selectedTitleBoxIDs)
            session.fields.title = combinedText(from: session.selectedTitleBoxIDs)
        case .artist:
            hasUserModifiedArtist = true
            toggleID(box.id, in: &session.selectedArtistBoxIDs)
            session.fields.artist = combinedText(from: session.selectedArtistBoxIDs)
        case .catalog:
            hasUserModifiedCatalog = true
            toggleID(box.id, in: &session.selectedCatalogBoxIDs)
            session.fields.catalogNumber = combinedText(from: session.selectedCatalogBoxIDs)
        }
    }

    func updateOCRText(boxID: UUID, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = session.ocrBoxes.firstIndex(where: { $0.id == boxID })
        else {
            return
        }

        session.ocrBoxes[idx].text = trimmed
        session.fields.title = combinedText(from: session.selectedTitleBoxIDs)
        session.fields.artist = combinedText(from: session.selectedArtistBoxIDs)
        session.fields.catalogNumber = combinedText(from: session.selectedCatalogBoxIDs)
        session.rawOCRText = session.ocrBoxes
            .sorted(by: Self.readingOrder)
            .map(\.text)
            .joined(separator: "\n")
    }

    func clearSelection(for mode: OCRSelectionMode) {
        switch mode {
        case .title:
            hasUserModifiedTitle = true
            session.selectedTitleBoxIDs = []
            session.fields.title = ""
        case .artist:
            hasUserModifiedArtist = true
            session.selectedArtistBoxIDs = []
            session.fields.artist = ""
        case .catalog:
            hasUserModifiedCatalog = true
            session.selectedCatalogBoxIDs = []
            session.fields.catalogNumber = ""
        }
    }

    func isBoxSelected(_ id: UUID) -> Bool {
        session.selectedTitleBoxIDs.contains(id)
            || session.selectedArtistBoxIDs.contains(id)
            || session.selectedCatalogBoxIDs.contains(id)
    }

    func isBoxSelectedInActiveMode(_ id: UUID) -> Bool {
        switch selectionMode {
        case .title:
            return session.selectedTitleBoxIDs.contains(id)
        case .artist:
            return session.selectedArtistBoxIDs.contains(id)
        case .catalog:
            return session.selectedCatalogBoxIDs.contains(id)
        }
    }

    func selectionState(for id: UUID) -> OCRSelectionState {
        if isBoxSelectedInActiveMode(id) {
            return .selectedInCurrentMode
        }
        if isBoxSelected(id) {
            return .selectedInOtherMode
        }
        return .unselected
    }

    func save() {
        guard canSave else {
            saveMessage = artistValidationMessage
            return
        }

        let item = RecordItem(
            imagePath: session.imagePath,
            correctedCropPath: session.correctedCropPath,
            rawOCRText: session.rawOCRText,
            ocrBoxes: session.ocrBoxes,
            selectedTitleBoxIDs: session.selectedTitleBoxIDs,
            selectedArtistBoxIDs: session.selectedArtistBoxIDs,
            selectedCatalogBoxIDs: session.selectedCatalogBoxIDs,
            editableFields: session.fields,
            queryHistory: session.lookupHistory,
            latestCandidates: session.candidates,
            selectedDiscogsMatch: session.selectedDiscogsMatch,
            confirmedDiscogsSummary: session.confirmedDiscogsSummary,
            confirmedDiscogsRelease: session.confirmedDiscogsRelease,
            unresolved: session.unresolved,
            tags: session.tags
        )

        do {
            try repository.save(item)
            saveMessage = "Saved locally"
        } catch {
            saveMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func appendTag(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !session.tags.contains(trimmed) {
            session.tags.append(trimmed)
        }
    }

    private func toggleID(_ id: UUID, in array: inout [UUID]) {
        if let idx = array.firstIndex(of: id) {
            array.remove(at: idx)
        } else {
            array.append(id)
        }
    }

    private func combinedText(from ids: [UUID]) -> String {
        let selected = session.ocrBoxes.filter { ids.contains($0.id) }
            .sorted(by: Self.readingOrder)
            .map(\.text)
        return selected.joined(separator: " ")
    }

    private static func rank(box: OCRTextBox, originalIndex: Int) -> (score: Double, likelyType: OCRLikelyType, hint: String?) {
        let text = box.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return (-1000 - Double(originalIndex), .unknown, nil)
        }

        let length = text.count
        let hasDigits = text.rangeOfCharacter(from: .decimalDigits) != nil
        let hasHyphen = text.contains("-")
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols)
        let punctuationCount = text.unicodeScalars.filter { punctuation.contains($0) }.count
        let alphaNumericCount = text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        let onlyNoise = alphaNumericCount == 0

        var catalogScore = hasDigits ? 30 : 0
        if hasDigits && hasHyphen {
            catalogScore += 18
        }
        if hasDigits && text.range(of: #"[A-Za-z]{1,6}[\-\s]?[A-Za-z0-9]{1,10}[\-\s]?[0-9]{1,6}"#, options: .regularExpression) != nil {
            catalogScore += 15
        }

        var languageScore = 0
        if containsKanaOrKanji(text) {
            languageScore += 10
        }

        var titleScore = languageScore
        var artistScore = languageScore
        if (4...36).contains(length) {
            titleScore += 10
            artistScore += 8
        }
        if text.contains("・") || text.contains("/") || text.contains("&") {
            artistScore += 6
        }

        var baseScore = Double(box.confidence) * 10.0
        if hasDigits { baseScore += 8 }
        if onlyNoise { baseScore -= 40 }
        if length <= 2 { baseScore -= 20 }
        if punctuationCount >= max(2, length / 2) { baseScore -= 15 }

        let likelyType: OCRLikelyType
        let bestSemantic = max(catalogScore, titleScore, artistScore)
        if bestSemantic == catalogScore, catalogScore > 0 {
            likelyType = .catalog
            baseScore += Double(catalogScore)
        } else if bestSemantic == artistScore, artistScore > 0 {
            likelyType = .artist
            baseScore += Double(artistScore)
        } else if bestSemantic == titleScore, titleScore > 0 {
            likelyType = .title
            baseScore += Double(titleScore)
        } else {
            likelyType = .unknown
        }

        if (4...80).contains(length), !onlyNoise, !hasDigits, likelyType != .unknown {
            baseScore += 2
        }

        let hint: String?
        if likelyType == .artist || likelyType == .title {
            hint = isLikelyHumanReadableNameOrTitle(text) ? "Looks valid" : "Check spacing/characters"
        } else {
            hint = nil
        }

        return (baseScore - Double(originalIndex) * 0.01, likelyType, hint)
    }

    private func applyInitialBestSelectionsIfNeeded() {
        guard !session.ocrBoxes.isEmpty else { return }

        if !hasUserModifiedTitle,
           session.selectedTitleBoxIDs.isEmpty,
           session.fields.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let titleBox = bestCandidate(for: .title) {
            session.selectedTitleBoxIDs = [titleBox.id]
            session.fields.title = titleBox.text
        }

        if !hasUserModifiedArtist,
           session.selectedArtistBoxIDs.isEmpty,
           session.fields.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let artistBox = bestCandidate(for: .artist) {
            session.selectedArtistBoxIDs = [artistBox.id]
            session.fields.artist = artistBox.text
        }

        if !hasUserModifiedCatalog,
           session.selectedCatalogBoxIDs.isEmpty,
           session.fields.catalogNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let catalogBox = bestCandidate(for: .catalog) {
            session.selectedCatalogBoxIDs = [catalogBox.id]
            session.fields.catalogNumber = catalogBox.text
        }
    }

    private func bestCandidate(for mode: OCRSelectionMode) -> OCRTextBox? {
        rankedOCRCandidates.first(where: { candidate in
            switch mode {
            case .title:
                return candidate.likelyType == .title
            case .artist:
                return candidate.likelyType == .artist
            case .catalog:
                return candidate.likelyType == .catalog
            }
        })?.box
    }

    private static func containsKanaOrKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF:
                return true
            default:
                return false
            }
        }
    }

    private static func isLikelyHumanReadableNameOrTitle(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count >= 2 else { return false }
        let words = trimmed.split(separator: " ").count
        let hasLetter = trimmed.rangeOfCharacter(from: .letters) != nil
        let weird = trimmed.range(of: #"[\{\}\[\]|<>]{2,}"#, options: .regularExpression) != nil
        return hasLetter && words <= 8 && !weird
    }

    private func readingOrderBox(_ lhs: OCRTextBox, _ rhs: OCRTextBox) -> Bool {
        Self.readingOrder(lhs: lhs, rhs: rhs)
    }

    private static func readingOrder(lhs: OCRTextBox, rhs: OCRTextBox) -> Bool {
        let leftY = lhs.normalizedRect.y
        let rightY = rhs.normalizedRect.y
        if abs(leftY - rightY) > 0.02 {
            return leftY > rightY
        }
        return lhs.normalizedRect.x < rhs.normalizedRect.x
    }
}
