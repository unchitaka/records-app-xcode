import Foundation
internal import Combine

@MainActor
final class SavedRecordsListViewModel: ObservableObject {
    @Published var items: [RecordItem] = []
    @Published var error: String?

    let repository: RecordRepository
    let unresolvedOnly: Bool

    init(repository: RecordRepository, unresolvedOnly: Bool) {
        self.repository = repository
        self.unresolvedOnly = unresolvedOnly
        load()
    }

    func load() {
        do {
            items = try repository.fetchAll(unresolvedOnly: unresolvedOnly)
        } catch {
            self.error = "Failed to load records"
        }
    }
}
