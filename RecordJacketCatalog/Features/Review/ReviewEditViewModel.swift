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
            session.candidates = candidates
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

    func confirmCandidate(_ candidate: DiscogsCandidate) async {
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

    func toggleSelection(for box: OCRTextBox) {
        switch selectionMode {
        case .title:
            toggleID(box.id, in: &session.selectedTitleBoxIDs)
            session.fields.title = combinedText(from: session.selectedTitleBoxIDs)
        case .artist:
            toggleID(box.id, in: &session.selectedArtistBoxIDs)
            session.fields.artist = combinedText(from: session.selectedArtistBoxIDs)
        case .catalog:
            toggleID(box.id, in: &session.selectedCatalogBoxIDs)
            session.fields.catalogNumber = combinedText(from: session.selectedCatalogBoxIDs)
        }
    }

    func clearSelection(for mode: OCRSelectionMode) {
        switch mode {
        case .title:
            session.selectedTitleBoxIDs = []
            session.fields.title = ""
        case .artist:
            session.selectedArtistBoxIDs = []
            session.fields.artist = ""
        case .catalog:
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

    private static func readingOrder(lhs: OCRTextBox, rhs: OCRTextBox) -> Bool {
        let leftY = lhs.normalizedRect.y
        let rightY = rhs.normalizedRect.y
        if abs(leftY - rightY) > 0.02 {
            return leftY > rightY
        }
        return lhs.normalizedRect.x < rhs.normalizedRect.x
    }
}
