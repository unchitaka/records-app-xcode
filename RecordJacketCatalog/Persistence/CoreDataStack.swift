import CoreData
import Foundation

final class CoreDataStack {
    let container: NSPersistentContainer

    init(logger: AppLogger) {
        guard let modelURL = Bundle.main.url(forResource: "RecordModel", withExtension: "momd") else {
            logger.error("Missing RecordModel.momd in app bundle")
            fatalError("Core Data model not found")
        }

        guard let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL) else {
            logger.error("Unable to load managed object model from \(modelURL.path)")
            fatalError("Core Data model invalid")
        }

        container = NSPersistentContainer(name: "RecordModel", managedObjectModel: managedObjectModel)

        container.loadPersistentStores { _, error in
            if let error {
                logger.error("Core Data failed to load: \(error.localizedDescription)")
                fatalError("Core Data load failed")
            } else {
                logger.info("Core Data loaded")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
