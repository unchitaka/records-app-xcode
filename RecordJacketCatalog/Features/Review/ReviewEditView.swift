import SwiftUI

struct ReviewEditView: View {
    @StateObject var viewModel: ReviewEditViewModel
    let onSaved: () -> Void

    @State private var newTag = ""

    var body: some View {
        Form {
            if viewModel.session.glareWarning {
                Text("Potential glare detected. Consider recapturing for better OCR.")
                    .foregroundStyle(.orange)
            }

            Picker("Stage", selection: $viewModel.stage) {
                ForEach(ReviewEditViewModel.EditStage.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.stage == .basic || viewModel.stage == .advanced || viewModel.stage == .lookup {
                Section("Basic fields") {
                    TextField("Title", text: $viewModel.session.fields.title)
                    TextField("Artist", text: $viewModel.session.fields.artist)
                    TextField("Catalog #", text: $viewModel.session.fields.catalogNumber)
                }
            }

            if viewModel.stage == .advanced || viewModel.stage == .lookup {
                Section("More fields") {
                    TextField("Label", text: $viewModel.session.fields.label)
                    TextField("Year", text: $viewModel.session.fields.year)
                }
            }

            if viewModel.stage == .lookup {
                Section("Discogs") {
                    Button(viewModel.isLookingUp ? "Looking up..." : "Re-run Discogs Lookup") {
                        Task { await viewModel.runLookup() }
                    }
                    .disabled(viewModel.isLookingUp)

                    if let lookupError = viewModel.lookupError {
                        Text(lookupError).foregroundStyle(.red)
                    }

                    ForEach(viewModel.session.candidates) { candidate in
                        Button {
                            viewModel.selectCandidate(candidate)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(candidate.title).font(.headline)
                                Text([candidate.year, candidate.country, candidate.format]
                                    .compactMap { $0 }
                                    .joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Save as unresolved") {
                        viewModel.selectCandidate(nil)
                    }
                }
            }

            Section("Tags") {
                HStack {
                    TextField("Add tag", text: $newTag)
                    Button("Add") {
                        viewModel.appendTag(newTag)
                        newTag = ""
                    }
                }
                if !viewModel.session.tags.isEmpty {
                    Text(viewModel.session.tags.joined(separator: ", "))
                }
            }

            Section {
                Button("Finalize / Save") {
                    viewModel.save()
                    if viewModel.saveMessage == "Saved locally" {
                        onSaved()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            if let message = viewModel.saveMessage {
                Text(message)
            }
        }
        .navigationTitle("Review & Edit")
    }
}
