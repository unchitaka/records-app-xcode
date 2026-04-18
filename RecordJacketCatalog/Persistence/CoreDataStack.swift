// CoreDataStack.swift
import CoreData
import Foundation

final class CoreDataStack {
    let container: NSPersistentContainer

    init(logger: AppLogger) {
        container = NSPersistentContainer(name: "RecordModel") // MUST match .xcdatamodeld name

        container.loadPersistentStores { _, error in
            if let error {
                logger.error("Core Data failed to load: \(error.localizedDescription)")
                fatalError("Core Data load failed")
            } else {
                logger.info("Core Data loaded")
            }
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}   
