import SwiftUI
import UIKit

struct ReviewEditView: View {
    @StateObject var viewModel: ReviewEditViewModel
    let onSaved: () -> Void
    let onRestart: () -> Void

    @State private var newTag = ""
    @State private var editingBox: OCRTextBox?
    @State private var editedOCRText = ""

    private var isEditingPresented: Binding<Bool> {
        Binding(
            get: { editingBox != nil },
            set: { isPresented in
                if !isPresented {
                    editingBox = nil
                }
            }
        )
    }

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
                    imagePath: viewModel.session.preferredImagePath,
                    boxes: viewModel.session.ocrBoxes,
                    isBoxSelected: { box in viewModel.isBoxSelected(box.id) },
                    isBoxSelectedInMode: { box in viewModel.isBoxSelectedInActiveMode(box.id) }
                )
                .frame(height: 280)

                Picker("Selection Mode", selection: $viewModel.selectionMode) {
                    ForEach(OCRSelectionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.session.ocrBoxes.isEmpty {
                    Text("No OCR items recognized.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.rankedOCRCandidates) { candidate in
                        Button {
                            viewModel.toggleSelection(for: candidate.box)
                        } label: {
                            OCRListRow(
                                text: candidate.box.text,
                                confidence: candidate.box.confidence,
                                state: viewModel.selectionState(for: candidate.box.id),
                                likelyType: candidate.likelyType,
                                hint: candidate.hint
                            )
                        }
                        .buttonStyle(.plain)
                        .onLongPressGesture {
                            beginEditing(candidate.box)
                        }
                    }
                }
            }

            if viewModel.stage == .basic || viewModel.stage == .advanced || viewModel.stage == .lookup {
                Section("Basic fields") {
                    editableRow(title: "Title", text: $viewModel.session.fields.title, clearMode: .title)
                    editableRow(title: "Artist", text: $viewModel.session.fields.artist, clearMode: .artist)

                    if let validation = viewModel.artistValidationMessage {
                        Text(validation)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

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

                    Button(
                        viewModel.isConfirmingCandidate
                        ? "Confirming..."
                        : "Confirm Selected Match"
                    ) {
                        Task { await viewModel.confirmSelectedCandidate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isConfirmingCandidate || viewModel.selectedCandidate == nil)

                    Button("Save as unresolved") {
                        viewModel.saveAsUnresolved()
                        if viewModel.saveMessage == "Saved locally" {
                            onSaved()
                        }
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
                .disabled(!viewModel.canSave)

                Button("Restart / Recapture", role: .destructive) {
                    onRestart()
                }
            }

            if let message = viewModel.saveMessage {
                Text(message)
                    .foregroundStyle(viewModel.canSave ? Color.secondary : Color.red)
            }
        }
        .navigationTitle("Review & Edit")
        .alert("Edit OCR Candidate", isPresented: isEditingPresented) {
            TextField("OCR text", text: $editedOCRText)
            Button("Cancel", role: .cancel) {
                editingBox = nil
            }
            Button("Save") {
                guard let box = editingBox else { return }
                viewModel.updateOCRText(boxID: box.id, newText: editedOCRText)
                editingBox = nil
            }
        } message: {
            Text("Long-press lets you correct OCR text while preserving the same OCR item.")
        }
    }

    private func beginEditing(_ box: OCRTextBox) {
        editingBox = box
        editedOCRText = box.text
    }

    @ViewBuilder
    private func editableRow(title: String, text: Binding<String>, clearMode: OCRSelectionMode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
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

private struct OCRListRow: View {
    let text: String
    let confidence: Float
    let state: ReviewEditViewModel.OCRSelectionState
    let likelyType: ReviewEditViewModel.OCRLikelyType
    let hint: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    if likelyType != .unknown {
                        Text(likelyType.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.thinMaterial, in: Capsule())
                    }

                    Text("Confidence: \(Int((confidence * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let hint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var iconName: String {
        switch state {
        case .selectedInCurrentMode:
            return "checkmark.circle.fill"
        case .selectedInOtherMode:
            return "circle.dashed"
        case .unselected:
            return "circle"
        }
    }

    private var iconColor: Color {
        switch state {
        case .selectedInCurrentMode:
            return .green
        case .selectedInOtherMode:
            return .blue
        case .unselected:
            return .secondary
        }
    }
}

private struct DiscogsCandidateRow: View {
    let candidate: DiscogsCandidate
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? .blue : .secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(.subheadline.weight(.semibold))
                Text(candidate.artist ?? "Unknown artist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Cat#: \(candidate.catalogNumber?.isEmpty == false ? candidate.catalogNumber! : "N/A")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                let metadata = [candidate.year, candidate.country].compactMap { $0 }.joined(separator: " · ")
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
