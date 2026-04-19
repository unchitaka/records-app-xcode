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

    func runLookup() async {
        isLookingUp = true
        lookupError = nil
        let query = [session.fields.artist, session.fields.title, session.fields.catalogNumber]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        session.lookupHistory.append(LookupQueryLog(query: query))

        do {
            let candidates = try await discogs.search(fields: session.fields)
            session.candidates = candidates

            if candidates.isEmpty {
                lookupError = "No Discogs matches found. Edit fields (especially catalog #) and retry."
                await tryCoverMatcherFallbackIfAvailable()
            }
        } catch let error as DiscogsLookupError {
            lookupError = error.errorDescription
        } catch {
            lookupError = "Unexpected lookup error. Please retry."
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

    func selectCandidate(_ candidate: DiscogsCandidate?) {
        session.selectedCandidateID = candidate?.id
        session.unresolved = candidate == nil
    }

    func save() {
        let selected = session.candidates.first(where: { $0.id == session.selectedCandidateID })
        let item = RecordItem(
            imagePath: session.imagePath,
            correctedCropPath: session.correctedCropPath,
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
