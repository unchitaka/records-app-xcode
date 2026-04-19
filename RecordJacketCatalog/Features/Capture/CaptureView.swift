import SwiftUI

struct CaptureView: View {
    @StateObject var viewModel: CaptureViewModel
    let onSessionCreated: (ReviewSession) -> Void

    var body: some View {
        VStack(spacing: 16) {
            CameraPreviewView(session: viewModel.previewSession)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
                .aspectRatio(3 / 4, contentMode: .fit)
                .padding(.top, 12)

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
}
