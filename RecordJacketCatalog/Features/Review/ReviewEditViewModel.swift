import Foundation
internal import Combine

@MainActor
final class ReviewEditViewModel: ObservableObject {
    
    @Published var session: ReviewSession
    @Published var isLookingUp = false
    @Published var lookupError: String?
    @Published var saveMessage: String?
    @Published var stage: EditStage = .basic

    private let repository: RecordRepository
    private let discogs: DiscogsLookupService

    init(session: ReviewSession, repository: RecordRepository, discogs: DiscogsLookupService) {
        self.session = session
        self.repository = repository
        self.discogs = discogs
    }

    enum EditStage: String, CaseIterable {
        case basic = "Basic"
        case advanced = "Advanced"
        case lookup = "Lookup"
    }

    func runLookup() async {
        isLookingUp = true
        lookupError = nil
        let query = [session.fields.artist, session.fields.title, session.fields.catalogNumber]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        session.lookupHistory.append(LookupQueryLog(query: query))

        do {
            session.candidates = try await discogs.search(fields: session.fields)
        } catch {
            lookupError = "Discogs lookup failed. Check token/network and retry."
        }

        isLookingUp = false
    }

    func selectCandidate(_ candidate: DiscogsCandidate?) {
        session.selectedCandidateID = candidate?.id
        session.unresolved = candidate == nil
    }

    func save() {
        let selected = session.candidates.first(where: { $0.id == session.selectedCandidateID })
        let item = RecordItem(
            imagePath: session.imagePath,
            rawOCRText: session.rawOCRText,
            editableFields: session.fields,
            queryHistory: session.lookupHistory,
            latestCandidates: session.candidates,
            selectedDiscogsMatch: selected,
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
}
