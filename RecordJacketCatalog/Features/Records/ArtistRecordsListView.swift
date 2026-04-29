import SwiftUI
import UIKit

struct ArtistRecordsListView: View {
    let artistName: String
    let records: [RecordItem]

    var body: some View {
        List(records) { item in
            NavigationLink {
                RecordDetailView(record: item)
            } label: {
                HStack(spacing: 12) {
                    RecordThumbnailView(imagePaths: item.candidateImagePaths, size: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.editableFields.title.isEmpty ? "(Untitled)" : item.editableFields.title)
                            .font(.headline)
                        Text(item.editableFields.catalogNumber)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if records.isEmpty {
                ContentUnavailableView("No records", systemImage: "opticaldisc")
            }
        }
        .navigationTitle(artistName)
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
