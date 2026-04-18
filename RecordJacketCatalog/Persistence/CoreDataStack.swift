import CoreData
import Foundation

final class CoreDataStack {
    let container: NSPersistentContainer

    init(modelName: String, logger: AppLogger) {
        container = NSPersistentContainer(name: modelName)
        container.loadPersistentStores { _, error in
            if let error {
                logger.error("Core Data failed to load: \(error.localizedDescription)")
            } else {
                logger.info("Core Data loaded")
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
