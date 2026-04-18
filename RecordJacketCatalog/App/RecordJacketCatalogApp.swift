import SwiftUI

@main
struct RecordJacketCatalogApp: App {
    private let container = AppContainer.live

    var body: some Scene {
        WindowGroup {
            RootTabView(viewModel: RootTabViewModel(container: container))
        }
    }
}

struct AppContainer {
    let repository: RecordRepository
    let cameraService: CameraService
    let ocrService: OCRService
    let discogsService: DiscogsLookupService
    let logger: AppLogger

    static let live: AppContainer = {
        let logger = AppLogger(category: "App")
        return .init(
            repository: CoreDataRecordRepository(logger: logger),
            cameraService: AVCameraService(logger: logger),
            ocrService: VisionOCRService(logger: logger),
            discogsService: LiveDiscogsLookupService(logger: logger),
            logger: logger
        )
    }()
}
