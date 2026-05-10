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
            let fetched = try repository.fetchAll(unresolvedOnly: unresolvedOnly)
            items = fetched
            error = nil

            if unresolvedOnly {
                recordsByArtistKey = [:]
                artistBuckets = []
            } else {
                rebuildArtistIndex(from: fetched)
            }

            print("SavedRecordsListViewModel.load: unresolvedOnly=\(unresolvedOnly), items.count=\(items.count), artistBuckets.count=\(artistBuckets.count)")

            for item in items.prefix(5) {
                print(
                    "SavedRecordsListViewModel.load item: id=\(item.id.uuidString), title=\(item.editableFields.title), artist=\(resolvedArtistDisplayName(for: item)), unresolved=\(item.unresolved)"
                )
            }
        } catch {
            self.error = "Failed to load records: \(error.localizedDescription)"
            print("SavedRecordsListViewModel.load ERROR: \(error.localizedDescription)")
        }
    }

    var filteredUnresolvedItems: [RecordItem] {
        let query = unresolvedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sortedRecords(items) }

        return sortedRecords(
            items.filter { item in
                item.editableFields.title.localizedCaseInsensitiveContains(query)
                || item.editableFields.artist.localizedCaseInsensitiveContains(query)
                || resolvedArtistDisplayName(for: item).localizedCaseInsensitiveContains(query)
                || item.artistIndex.localizedCaseInsensitiveContains(query)
                || item.editableFields.catalogNumber.localizedCaseInsensitiveContains(query)
            }
        )
    }

    var filteredArtistBuckets: [ArtistBucket] {
        let rawQuery = artistSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = normalizedArtistKey(rawQuery)

        guard !rawQuery.isEmpty else { return artistBuckets }

        return artistBuckets.filter {
            $0.displayName.localizedCaseInsensitiveContains(rawQuery)
            || $0.normalizedName.contains(normalizedQuery)
        }
    }

    var filteredSavedFallbackItems: [RecordItem] {
        let rawQuery = artistSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawQuery.isEmpty else { return sortedRecords(items) }

        return sortedRecords(
            items.filter { item in
                item.editableFields.title.localizedCaseInsensitiveContains(rawQuery)
                || resolvedArtistDisplayName(for: item).localizedCaseInsensitiveContains(rawQuery)
                || item.editableFields.catalogNumber.localizedCaseInsensitiveContains(rawQuery)
                || item.artistIndex.localizedCaseInsensitiveContains(rawQuery)
            }
        )
    }

    var shouldUseSavedFallbackList: Bool {
        !unresolvedOnly && !items.isEmpty && artistBuckets.isEmpty
    }

    func records(for artistBucket: ArtistBucket) -> [RecordItem] {
        sortedRecords(recordsByArtistKey[artistBucket.normalizedName] ?? [])
    }

    func resolvedArtistDisplayName(for record: RecordItem) -> String {
        let explicit = record.editableFields.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }

        let discogs = record.confirmedDiscogsSummary?.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !discogs.isEmpty { return discogs }

        let selectedDiscogs = record.selectedDiscogsMatch?.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !selectedDiscogs.isEmpty { return selectedDiscogs }

        let indexArtist = record.artistIndex.trimmingCharacters(in: .whitespacesAndNewlines)
        if !indexArtist.isEmpty, indexArtist.lowercased() != "unknown artist" {
            return indexArtist
        }

        return "Unknown Artist"
    }

    private func rebuildArtistIndex(from records: [RecordItem]) {
        var grouped: [String: [RecordItem]] = [:]
        var displayNameByKey: [String: String] = [:]

        for record in records {
            let display = resolvedArtistDisplayName(for: record)
            let key = normalizedArtistKey(display)

            grouped[key, default: []].append(record)

            if displayNameByKey[key] == nil {
                displayNameByKey[key] = display
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

        print("SavedRecordsListViewModel.rebuildArtistIndex: records=\(records.count), buckets=\(artistBuckets.count)")
    }

    private func sortedRecords(_ records: [RecordItem]) -> [RecordItem] {
        records.sorted { lhs, rhs in
            let lhsTitle = lhs.editableFields.title.isEmpty ? "(Untitled)" : lhs.editableFields.title
            let rhsTitle = rhs.editableFields.title.isEmpty ? "(Untitled)" : rhs.editableFields.title

            let artistOrder = resolvedArtistDisplayName(for: lhs)
                .localizedCaseInsensitiveCompare(resolvedArtistDisplayName(for: rhs))

            if artistOrder != .orderedSame {
                return artistOrder == .orderedAscending
            }

            let titleOrder = lhsTitle.localizedCaseInsensitiveCompare(rhsTitle)
            if titleOrder == .orderedSame {
                return lhs.updatedAt > rhs.updatedAt
            }

            return titleOrder == .orderedAscending
        }
    }

    private func normalizedArtistKey(_ value: String) -> String {
        RecordItem.normalizedArtistIndex(value)
    }
}
