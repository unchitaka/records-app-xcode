import CoreData
import Foundation

protocol RecordRepository {
    func save(_ item: RecordItem) throws
    func fetchAll(unresolvedOnly: Bool) throws -> [RecordItem]
    func fetch(id: UUID) throws -> RecordItem?
}

final class CoreDataRecordRepository: RecordRepository {
    private let logger: AppLogger
    private let stack: CoreDataStack

    init(logger: AppLogger) {
        self.logger = logger
        self.stack = CoreDataStack(modelName: "RecordModel", logger: logger)
    }

    func save(_ item: RecordItem) throws {
        logger.info("Saving record \(item.id)")
        let context = stack.container.viewContext

        let request = NSFetchRequest<NSManagedObject>(entityName: "StoredRecord")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", item.id as CVarArg)

        let entity = try context.fetch(request).first ?? NSManagedObject(entity: NSEntityDescription.entity(forEntityName: "StoredRecord", in: context)!, insertInto: context)

        entity.setValue(item.id, forKey: "id")
        entity.setValue(item.createdAt, forKey: "createdAt")
        entity.setValue(Date(), forKey: "updatedAt")
        entity.setValue(item.imagePath, forKey: "imagePath")
        entity.setValue(item.correctedCropPath, forKey: "correctedCropPath")
        entity.setValue(item.rawOCRText, forKey: "rawOCRText")
        entity.setValue(try encode(item.editableFields), forKey: "editableFields")
        entity.setValue(try encode(item.queryHistory), forKey: "queryHistory")
        entity.setValue(try encode(item.latestCandidates), forKey: "latestCandidates")
        entity.setValue(try encode(item.selectedDiscogsMatch), forKey: "selectedMatch")
        entity.setValue(item.unresolved, forKey: "unresolved")
        entity.setValue(try encode(item.tags), forKey: "tags")

        try context.save()
    }

    func fetchAll(unresolvedOnly: Bool) throws -> [RecordItem] {
        let context = stack.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "StoredRecord")
        if unresolvedOnly {
            request.predicate = NSPredicate(format: "unresolved == YES")
        }
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        return try context.fetch(request).compactMap(mapManagedObject)
    }

    func fetch(id: UUID) throws -> RecordItem? {
        let context = stack.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "StoredRecord")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first.flatMap(mapManagedObject)
    }

    private func encode<T: Codable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func decode<T: Codable>(_ data: Data?, fallback: T) -> T {
        guard let data else { return fallback }
        return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
    }

    private func mapManagedObject(_ object: NSManagedObject) -> RecordItem? {
        guard
            let id = object.value(forKey: "id") as? UUID,
            let createdAt = object.value(forKey: "createdAt") as? Date,
            let updatedAt = object.value(forKey: "updatedAt") as? Date,
            let imagePath = object.value(forKey: "imagePath") as? String,
            let rawOCRText = object.value(forKey: "rawOCRText") as? String
        else {
            return nil
        }

        return RecordItem(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            imagePath: imagePath,
            correctedCropPath: object.value(forKey: "correctedCropPath") as? String,
            rawOCRText: rawOCRText,
            editableFields: decode(object.value(forKey: "editableFields") as? Data, fallback: .empty),
            queryHistory: decode(object.value(forKey: "queryHistory") as? Data, fallback: []),
            latestCandidates: decode(object.value(forKey: "latestCandidates") as? Data, fallback: []),
            selectedDiscogsMatch: decode(object.value(forKey: "selectedMatch") as? Data, fallback: Optional<DiscogsCandidate>.none),
            unresolved: object.value(forKey: "unresolved") as? Bool ?? true,
            tags: decode(object.value(forKey: "tags") as? Data, fallback: [])
        )
    }
}
