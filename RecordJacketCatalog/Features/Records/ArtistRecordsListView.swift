import SwiftUI

struct ArtistRecordsListView: View {
    let artistName: String
    let records: [RecordItem]

    var body: some View {
        List(records) { item in
            NavigationLink {
                RecordDetailView(record: item)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.editableFields.title.isEmpty ? "(Untitled)" : item.editableFields.title)
                        .font(.headline)
                    Text(item.editableFields.catalogNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
