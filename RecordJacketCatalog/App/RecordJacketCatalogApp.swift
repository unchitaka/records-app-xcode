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
    let coverImageMatcher: CoverImageMatchService
    let logger: AppLogger

    static let live: AppContainer = {
        let logger = AppLogger(category: "App")
#if targetEnvironment(simulator)
        let cameraService: CameraService = FixtureCameraService(logger: logger)
#else
        let cameraService: CameraService = AVCameraService(logger: logger)
#endif

        return .init(
            repository: CoreDataRecordRepository(logger: logger),
            cameraService: cameraService,
            ocrService: VisionOCRService(logger: logger),
            discogsService: LiveDiscogsLookupService(logger: logger),
            coverImageMatcher: StubCoverImageMatchService(logger: logger),
            logger: logger
        )
    }()
}
