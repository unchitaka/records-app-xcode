import SwiftUI

struct CaptureFlowHostView: View {
    let container: AppContainer

    @State private var session: ReviewSession?

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    ReviewEditView(
                        viewModel: .init(
                            session: session,
                            repository: container.repository,
                            discogs: container.discogsService,
                            coverMatcher: container.coverImageMatcher
                        )
                    ) {
                        self.session = nil
                    }
                } else {
                    CaptureView(viewModel: .init(camera: container.cameraService, ocr: container.ocrService, logger: container.logger)) { created in
                        self.session = created
                    }
                }
            }
            .navigationTitle("Record Scanner")
        }
    }
}
