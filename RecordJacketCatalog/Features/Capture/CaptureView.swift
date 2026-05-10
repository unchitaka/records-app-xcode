import SwiftUI
import UIKit

struct CaptureView: View {
    @StateObject var viewModel: CaptureViewModel
    let onSessionCreated: (ReviewSession) -> Void

    var body: some View {
        VStack(spacing: 16) {
            preview
                .padding(.top, 12)

            if !viewModel.fixtureNames.isEmpty {
                Picker("Fixture", selection: Binding(
                    get: { viewModel.selectedFixtureIndex },
                    set: { viewModel.selectFixture(at: $0) }
                )) {
                    ForEach(Array(viewModel.fixtureNames.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            Button {
                viewModel.captureAndRunOCR(onComplete: onSessionCreated)
            } label: {
                Label(viewModel.isBusy ? "Processing..." : "Tap Capture", systemImage: "camera.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isBusy)
        }
        .padding(.horizontal, 16)
        .onAppear(perform: viewModel.onAppear)
        .onDisappear(perform: viewModel.onDisappear)
    }

    @ViewBuilder
    private var preview: some View {
        if let image = viewModel.selectedFixtureImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .overlay(alignment: .bottomLeading) {
                    if let name = viewModel.selectedFixtureName {
                        Text(name)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                            .padding(12)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
                .aspectRatio(3 / 4, contentMode: .fit)
        } else {
            CameraPreviewView(session: viewModel.previewSession)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
                .aspectRatio(3 / 4, contentMode: .fit)
        }
    }
}
