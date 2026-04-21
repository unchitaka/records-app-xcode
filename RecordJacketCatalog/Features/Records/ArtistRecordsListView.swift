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
                    if let image = UIImage(contentsOfFile: item.preferredImagePath) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "photo")
                            .frame(width: 52, height: 52)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

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
