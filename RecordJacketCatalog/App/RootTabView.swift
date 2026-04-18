import SwiftUI
internal import Combine

final class RootTabViewModel: ObservableObject {
    let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }
}

struct RootTabView: View {
    @StateObject var viewModel: RootTabViewModel

    var body: some View {
        TabView {
            CaptureFlowHostView(container: viewModel.container)
                .tabItem {
                    Label("Capture", systemImage: "camera")
                }

            SavedRecordsListView(viewModel: .init(repository: viewModel.container.repository, unresolvedOnly: false))
                .tabItem {
                    Label("Saved", systemImage: "square.stack")
                }

            SavedRecordsListView(viewModel: .init(repository: viewModel.container.repository, unresolvedOnly: true))
                .tabItem {
                    Label("Unresolved", systemImage: "questionmark.circle")
                }
        }
    }
}
