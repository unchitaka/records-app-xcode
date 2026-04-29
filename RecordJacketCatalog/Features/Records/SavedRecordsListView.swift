import SwiftUI
import UIKit

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
        List(viewModel.filteredUnresolvedItems) { item in
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
                    },
                    onRestart: {
                        viewModel.load()
                    }
                )
            } label: {
                HStack(spacing: 12) {
                    RecordThumbnailView(imagePaths: item.candidateImagePaths, size: 52)

                    VStack(alignment: .leading) {
                        Text(item.editableFields.title.isEmpty ? "(Untitled)" : item.editableFields.title)
                            .font(.headline)
                        Text(item.editableFields.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if viewModel.filteredUnresolvedItems.isEmpty {
                ContentUnavailableView("No unresolved records", systemImage: "tray")
            }
        }
        .searchable(text: $viewModel.unresolvedSearchText, prompt: "Search unresolved artists")
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

private struct RecordThumbnailView: View {
    let imagePaths: [String]
    let size: CGFloat

    var body: some View {
        Group {
            if let image = loadImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .foregroundStyle(.secondary)
                    .background(.thinMaterial)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadImage() -> UIImage? {
        for path in imagePaths {
            if let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }
}
