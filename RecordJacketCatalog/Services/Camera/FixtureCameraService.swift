import AVFoundation
import Foundation

#if targetEnvironment(simulator)
final class FixtureCameraService: CameraService {
    private let logger: AppLogger
    private let fixtures: [CameraFixture]
    private(set) var selectedFixtureIndex = 0

    init(logger: AppLogger) {
        self.logger = logger
        self.fixtures = [
            CameraFixture(
                name: "Test Jacket 1",
                resourceName: "camera-test-1",
                resourceExtension: "jpeg",
                fields: EditableFields(
                    title: "プリンセスではないけれど / 涙のバースデイ・パーティ",
                    artist: "園まり",
                    catalogNumber: "DJ-1393",
                    label: "",
                    year: ""
                )
            ),
            CameraFixture(
                name: "Test Jacket 2",
                resourceName: "camera-test-2",
                resourceExtension: "jpeg",
                fields: EditableFields(
                    title: "蛍の光 / あおげばとうとし",
                    artist: "真理ヨシコ / 杉並児童合唱団",
                    catalogNumber: "BK-208",
                    label: "",
                    year: ""
                )
            ),
            CameraFixture(
                name: "Test Jacket 3",
                resourceName: "camera-test-3",
                resourceExtension: "jpeg",
                fields: EditableFields(
                    title: "忘れな草 / かわらぬ愛を",
                    artist: "ペギー葉山",
                    catalogNumber: "SEA-7",
                    label: "",
                    year: ""
                )
            ),
            CameraFixture(
                name: "Test Jacket 4",
                resourceName: "camera-test-4",
                resourceExtension: "jpeg",
                fields: EditableFields(
                    title: "こいのぼり / 鯉のぼり",
                    artist: "真理ヨシコ",
                    catalogNumber: "SC-74",
                    label: "",
                    year: ""
                )
            )
        ]
    }

    var isSessionRunning: Bool { false }
    var previewSession: AVCaptureSession? { nil }
    var fixtureNames: [String] { fixtures.map(\.name) }

    var selectedFixtureName: String? {
        guard fixtures.indices.contains(selectedFixtureIndex) else { return nil }
        return fixtures[selectedFixtureIndex].name
    }

    var selectedFixtureImageData: Data? {
        loadSelectedFixture()
    }

    var selectedFixtureFields: EditableFields? {
        guard fixtures.indices.contains(selectedFixtureIndex) else { return nil }
        return fixtures[selectedFixtureIndex].fields
    }

    func startSession() {}

    func stopSession() {}

    func selectFixture(at index: Int) {
        guard fixtures.indices.contains(index) else { return }
        selectedFixtureIndex = index
    }

    func capturePhoto(completion: @escaping (Result<Data, Error>) -> Void) {
        guard let data = loadSelectedFixture() else {
            logger.error("Fixture camera failed to load selected jacket image")
            completion(.failure(CameraError.fixtureUnavailable))
            return
        }

        completion(.success(data))
    }

    private func loadSelectedFixture() -> Data? {
        guard fixtures.indices.contains(selectedFixtureIndex) else { return nil }
        let fixture = fixtures[selectedFixtureIndex]

        guard let url = Bundle.main.url(forResource: fixture.resourceName, withExtension: fixture.resourceExtension) else {
            return nil
        }

        return try? Data(contentsOf: url)
    }
}

private struct CameraFixture {
    let name: String
    let resourceName: String
    let resourceExtension: String
    let fields: EditableFields
}
#endif
