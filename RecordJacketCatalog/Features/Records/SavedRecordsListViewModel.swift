import Foundation
internal import Combine

@MainActor
final class SavedRecordsListViewModel: ObservableObject {
    struct ArtistBucket: Identifiable {
        let normalizedName: String
        let displayName: String
        let count: Int

        var id: String { normalizedName }
    }

    @Published var items: [RecordItem] = []
    @Published var error: String?
    @Published var artistSearchText = ""
    @Published var unresolvedSearchText = ""
    @Published private(set) var artistBuckets: [ArtistBucket] = []

    let repository: RecordRepository
    let unresolvedOnly: Bool

    private var recordsByArtistKey: [String: [RecordItem]] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(repository: RecordRepository, unresolvedOnly: Bool) {
        self.repository = repository
        self.unresolvedOnly = unresolvedOnly

        NotificationCenter.default.publisher(for: .recordRepositoryDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.load()
            }
            .store(in: &cancellables)

        load()
    }

    func load() {
        do {
            items = try repository.fetchAll(unresolvedOnly: unresolvedOnly)
            error = nil

            if !unresolvedOnly {
                rebuildArtistIndex(from: items)
            }
        } catch {
            self.error = "Failed to load records"
        }
    }

    var filteredUnresolvedItems: [RecordItem] {
        let query = unresolvedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }

        return items.filter { item in
            item.editableFields.artist.localizedCaseInsensitiveContains(query)
            || item.artistIndex.localizedCaseInsensitiveContains(query)
        }
    }

    var filteredArtistBuckets: [ArtistBucket] {
        let query = normalizedArtistKey(artistSearchText)
        guard !query.isEmpty else { return artistBuckets }

        return artistBuckets.filter {
            $0.displayName.localizedCaseInsensitiveContains(artistSearchText)
                || $0.normalizedName.contains(query)
        }
    }

    func records(for artistBucket: ArtistBucket) -> [RecordItem] {
        (recordsByArtistKey[artistBucket.normalizedName] ?? []).sorted { lhs, rhs in
            let lhsTitle = lhs.editableFields.title.isEmpty ? "(Untitled)" : lhs.editableFields.title
            let rhsTitle = rhs.editableFields.title.isEmpty ? "(Untitled)" : rhs.editableFields.title
            let titleOrder = lhsTitle.localizedCaseInsensitiveCompare(rhsTitle)
            if titleOrder == .orderedSame {
                return lhs.updatedAt > rhs.updatedAt
            }
            return titleOrder == .orderedAscending
        }
    }

    private func rebuildArtistIndex(from records: [RecordItem]) {
        var grouped: [String: [RecordItem]] = [:]
        var displayNameByKey: [String: String] = [:]

        for record in records {
            let key = normalizedArtistKey(record.artistIndex)
            grouped[key, default: []].append(record)

            if displayNameByKey[key] == nil {
                displayNameByKey[key] = primaryArtist(from: record)
            }
        }

        recordsByArtistKey = grouped
        artistBuckets = grouped.keys.map { key in
            ArtistBucket(
                normalizedName: key,
                displayName: displayNameByKey[key] ?? "Unknown Artist",
                count: grouped[key]?.count ?? 0
            )
        }
        .sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func primaryArtist(from record: RecordItem) -> String {
        let explicit = record.editableFields.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }

        let discogs = record.confirmedDiscogsSummary?.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !discogs.isEmpty { return discogs }

        return "Unknown Artist"
    }

    private func normalizedArtistKey(_ value: String) -> String {
        RecordItem.normalizedArtistIndex(value)
    }
}
