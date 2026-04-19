import SwiftUI

struct SavedRecordsListView: View {
    @StateObject var viewModel: SavedRecordsListViewModel

    var body: some View {
        NavigationStack {
            List(viewModel.items) { item in
                NavigationLink {
                    if viewModel.unresolvedOnly {
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
                    } else {
                        RecordDetailView(record: item)
                    }
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
                    ContentUnavailableView("No records", systemImage: "tray")
                }
            }
            .navigationTitle(viewModel.unresolvedOnly ? "Unresolved" : "Saved")
            .onAppear { viewModel.load() }
        }
    }
}
