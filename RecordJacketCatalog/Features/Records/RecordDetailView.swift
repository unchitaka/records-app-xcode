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

            Section("OCR Selection") {
                row("Boxes", "\(record.ocrBoxes.count)")
                row("Title boxes", "\(record.selectedTitleBoxIDs.count)")
                row("Artist boxes", "\(record.selectedArtistBoxIDs.count)")
                row("Catalog boxes", "\(record.selectedCatalogBoxIDs.count)")
            }

            Section("Tags") {
                Text(record.tags.joined(separator: ", "))
            }

            Section("OCR Raw") {
                Text(record.rawOCRText)
                    .font(.caption)
            }

            if let summary = record.confirmedDiscogsSummary {
                Section("Confirmed Discogs") {
                    Text(summary.title)
                    Text(summary.resourceURL ?? "")
                        .font(.caption)
                }
            }

            if let release = record.confirmedDiscogsRelease {
                Section("Confirmed Release Details") {
                    row("Year", release.year.map(String.init) ?? "")
                    row("Country", release.country ?? "")
                    row("Formats", release.formats.map(\.name).joined(separator: ", "))
                    row("Labels", release.labels.map(\.name).joined(separator: ", "))
                    row("Catalog #", release.catalogNumbers.joined(separator: ", "))
                    row("Artists", release.artists.map(\.name).joined(separator: ", "))
                    row("Genres", release.genres.joined(separator: ", "))
                    row("Styles", release.styles.joined(separator: ", "))
                    row("Status", release.status ?? "")
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
