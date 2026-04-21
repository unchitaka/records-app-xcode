import SwiftUI

struct SavedRecordsListView: View {
    @StateObject var viewModel: SavedRecordsListViewModel

    var body: some View {
        NavigationStack {
            if viewModel.unresolvedOnly {
                unresolvedList
            } else {
                artistIndexList
            }
        }
    }

    private var unresolvedList: some View {
        List(viewModel.items) { item in
            NavigationLink {
                ReviewEditView(
                    viewModel: .init(
                        session: ReviewSession(record: item),
                        repository: viewModel.repository,
                        discogs: LiveDiscogsLookupService(logger: AppLogger(category: "RetryLookup")),
                        coverMatcher: StubCoverImageMatchService(logger: AppLogger(category: "RetryLookupCover"))
                    ),
                    onSaved: {
                        viewModel.load()
                    }
                )
            } label: {
                VStack(alignment: .leading) {
                    Text(item.editableFields.title.isEmpty ? "(Untitled)" : item.editableFields.title)
                        .font(.headline)
                    Text(item.editableFields.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if viewModel.items.isEmpty {
                ContentUnavailableView("No unresolved records", systemImage: "tray")
            }
        }
        .navigationTitle("Unresolved")
        .onAppear { viewModel.load() }
    }

    private var artistIndexList: some View {
        List(viewModel.filteredArtistBuckets) { bucket in
            NavigationLink {
                ArtistRecordsListView(
                    artistName: bucket.displayName,
                    records: viewModel.records(for: bucket)
                )
            } label: {
                HStack {
                    Text(bucket.displayName)
                    Spacer()
                    Text("\(bucket.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if viewModel.artistBuckets.isEmpty {
                ContentUnavailableView("No saved records", systemImage: "opticaldisc")
            }
        }
        .searchable(text: $viewModel.artistSearchText, prompt: "Search artists")
        .navigationTitle("Artists")
        .onAppear { viewModel.load() }
    }
}
