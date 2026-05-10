import SwiftUI
import UIKit

struct SavedRecordsListView: View {
    @StateObject var viewModel: SavedRecordsListViewModel

    init(viewModel: SavedRecordsListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.unresolvedOnly {
                    unresolvedList
                } else {
                    savedArtistOrFallbackList
                }
            }
            .onAppear {
                viewModel.load()
            }
            .refreshable {
                viewModel.load()
            }
        }
    }

    private var unresolvedList: some View {
        List(viewModel.filteredUnresolvedItems) { item in
            unresolvedNavigationRow(item)
        }
        .overlay {
            if viewModel.filteredUnresolvedItems.isEmpty {
                ContentUnavailableView("No unresolved records", systemImage: "tray")
            }
        }
        .searchable(text: $viewModel.unresolvedSearchText, prompt: "Search unresolved artists")
        .navigationTitle("Unresolved")
    }

    private var savedArtistOrFallbackList: some View {
        Group {
            if viewModel.shouldUseSavedFallbackList {
                savedFallbackList
            } else {
                savedArtistIndexScrollList
            }
        }
        .overlay {
            if viewModel.items.isEmpty {
                ContentUnavailableView("No saved records", systemImage: "opticaldisc")
            }
        }
        .searchable(text: $viewModel.artistSearchText, prompt: "Search artists")
        .navigationTitle("Artists")
    }

    private var savedArtistIndexScrollList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredArtistBuckets) { bucket in
                    NavigationLink {
                        ArtistRecordsListView(
                            artistName: bucket.displayName,
                            records: viewModel.records(for: bucket)
                        )
                    } label: {
                        artistBucketRow(bucket)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
    }

    private var savedFallbackList: some View {
        List(viewModel.filteredSavedFallbackItems) { item in
            NavigationLink {
                RecordDetailView(record: item)
            } label: {
                recordRow(item)
            }
        }
    }

    private func unresolvedNavigationRow(_ item: RecordItem) -> some View {
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
            recordRow(item)
        }
    }

    private func artistBucketRow(_ bucket: SavedRecordsListViewModel.ArtistBucket) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(bucket.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("\(bucket.count) record\(bucket.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func recordRow(_ item: RecordItem) -> some View {
        HStack(spacing: 12) {
            RecordThumbnailView(imagePaths: item.candidateImagePaths, size: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.editableFields.title.isEmpty ? "(Untitled)" : item.editableFields.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(viewModel.resolvedArtistDisplayName(for: item))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !item.editableFields.catalogNumber.isEmpty {
                    Text(item.editableFields.catalogNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
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
