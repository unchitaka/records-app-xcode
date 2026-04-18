import SwiftUI

struct RecordDetailView: View {
    let record: RecordItem

    var body: some View {
        Form {
            Section("Core") {
                row("Title", record.editableFields.title)
                row("Artist", record.editableFields.artist)
                row("Catalog", record.editableFields.catalogNumber)
                row("Unresolved", record.unresolved ? "Yes" : "No")
            }

            Section("Tags") {
                Text(record.tags.joined(separator: ", "))
            }

            Section("OCR Raw") {
                Text(record.rawOCRText)
                    .font(.caption)
            }

            if let match = record.selectedDiscogsMatch {
                Section("Selected Discogs") {
                    Text(match.title)
                    Text(match.resourceURL ?? "")
                        .font(.caption)
                }
            }

            Section("Candidates") {
                ForEach(record.latestCandidates) { c in
                    Text(c.title)
                }
            }
        }
        .navigationTitle("Record Detail")
    }

    @ViewBuilder
    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
