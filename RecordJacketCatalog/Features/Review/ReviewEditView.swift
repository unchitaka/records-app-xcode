import SwiftUI
import UIKit

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

            Section("OCR Input") {
                Text(viewModel.session.ocrInputSource == .correctedCrop
                     ? "OCR used corrected jacket crop"
                     : "OCR used original image fallback")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Picker("Stage", selection: $viewModel.stage) {
                ForEach(ReviewEditViewModel.EditStage.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)

            Section("OCR Selection") {
                OCRSelectionImageView(
                    imagePath: viewModel.session.correctedCropPath ?? viewModel.session.imagePath,
                    boxes: viewModel.session.ocrBoxes,
                    isBoxSelected: { box in viewModel.isBoxSelected(box.id) },
                    isBoxSelectedInMode: { box in viewModel.isBoxSelectedInActiveMode(box.id) },
                    onTapBox: { box in viewModel.toggleSelection(for: box) }
                )
                .frame(height: 280)

                Picker("Selection Mode", selection: $viewModel.selectionMode) {
                    ForEach(OCRSelectionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if viewModel.stage == .basic || viewModel.stage == .advanced || viewModel.stage == .lookup {
                Section("Basic fields") {
                    editableRow(title: "Title", text: $viewModel.session.fields.title, clearMode: .title)
                    editableRow(title: "Artist", text: $viewModel.session.fields.artist, clearMode: .artist)
                    editableRow(title: "Catalog #", text: $viewModel.session.fields.catalogNumber, clearMode: .catalog)
                }
            }

            if viewModel.stage == .advanced || viewModel.stage == .lookup {
                Section("More fields") {
                    TextField("Label", text: $viewModel.session.fields.label)
                    TextField("Year", text: $viewModel.session.fields.year)
                }

                Section("OCR Raw Text") {
                    Text(viewModel.session.rawOCRText)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }

            if viewModel.stage == .lookup {
                Section("Discogs") {
                    Button(viewModel.isLookingUp ? "Looking up..." : "Search Discogs Candidates") {
                        Task { await viewModel.runLookup() }
                    }
                    .disabled(viewModel.isLookingUp)

                    if let lookupError = viewModel.lookupError {
                        Text(lookupError).foregroundStyle(.red)
                    }

                    ForEach(viewModel.session.candidates) { candidate in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(candidate.title).font(.headline)
                            Text([candidate.year, candidate.country, candidate.format]
                                .compactMap { $0 }
                                .joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Button(
                                viewModel.isConfirmingCandidate && viewModel.session.selectedCandidateID == candidate.id
                                ? "Confirming..."
                                : "Confirm Match"
                            ) {
                                Task { await viewModel.confirmCandidate(candidate) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isConfirmingCandidate)
                        }
                    }

                    Button("Save as unresolved") {
                        viewModel.markUnresolved()
                    }
                }

                if let summary = viewModel.session.confirmedDiscogsSummary {
                    Section("Confirmed Discogs Candidate") {
                        Text(summary.title)
                        Text([summary.year, summary.country, summary.format].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let release = viewModel.session.confirmedDiscogsRelease {
                    Section("Confirmed Discogs Release") {
                        detailRow("Title", release.title)
                        detailRow("Year", release.year.map(String.init) ?? "")
                        detailRow("Country", release.country ?? "")
                        detailRow("Artists", release.artists.map(\.name).joined(separator: ", "))
                        detailRow("Labels", release.labels.map(\.name).joined(separator: ", "))
                        detailRow("Catalog #", release.catalogNumbers.joined(separator: ", "))
                        detailRow("Formats", release.formats.map(\.name).joined(separator: ", "))
                        detailRow("Genres", release.genres.joined(separator: ", "))
                        detailRow("Styles", release.styles.joined(separator: ", "))
                        detailRow("Status", release.status ?? "")
                        detailRow("URI", release.uri ?? "")
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

    @ViewBuilder
    private func editableRow(title: String, text: Binding<String>, clearMode: OCRSelectionMode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(title, text: text)
            Button("Clear OCR selection") {
                viewModel.clearSelection(for: clearMode)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func detailRow(_ key: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .top) {
                Text(key)
                Spacer()
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct OCRSelectionImageView: View {
    let imagePath: String
    let boxes: [OCRTextBox]
    let isBoxSelected: (OCRTextBox) -> Bool
    let isBoxSelectedInMode: (OCRTextBox) -> Bool
    let onTapBox: (OCRTextBox) -> Void

    var body: some View {
        GeometryReader { proxy in
            if let uiImage = UIImage(contentsOfFile: imagePath) {
                let imageSize = uiImage.size
                let containerSize = proxy.size
                let fitted = fittedRect(imageSize: imageSize, containerSize: containerSize)

                ZStack(alignment: .topLeading) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: containerSize.width, height: containerSize.height)

                    ForEach(boxes) { box in
                        let rect = convertRect(box.normalizedRect.cgRect, imageFrame: fitted)
                        Rectangle()
                            .strokeBorder(isBoxSelectedInMode(box) ? .green : (isBoxSelected(box) ? .blue : .yellow), lineWidth: 2)
                            .background(
                                Rectangle().fill((isBoxSelectedInMode(box) ? Color.green : Color.yellow).opacity(0.14))
                            )
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .contentShape(Rectangle())
                            .onTapGesture { onTapBox(box) }
                    }
                }
            } else {
                Text("Image preview unavailable")
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
    }

    private func fittedRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            return CGRect(x: 0, y: (containerSize.height - height) / 2, width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageAspect
            return CGRect(x: (containerSize.width - width) / 2, y: 0, width: width, height: height)
        }
    }

    private func convertRect(_ normalized: CGRect, imageFrame: CGRect) -> CGRect {
        let x = imageFrame.minX + normalized.minX * imageFrame.width
        let y = imageFrame.minY + (1 - normalized.maxY) * imageFrame.height
        let width = normalized.width * imageFrame.width
        let height = normalized.height * imageFrame.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
