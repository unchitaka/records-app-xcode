import CoreData
import Foundation

extension Notification.Name {
    static let recordRepositoryDidChange = Notification.Name("recordRepositoryDidChange")
}

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
        self.stack = CoreDataStack(logger: logger)
    }

    func save(_ item: RecordItem) throws {
        logger.info("Saving record \(item.id)")
        print("CoreDataRecordRepository.save: begin id=\(item.id.uuidString), unresolved=\(item.unresolved)")
        let context = stack.container.viewContext

        var saveError: Error?
        context.performAndWait {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: "StoredRecord")
                request.fetchLimit = 1
                request.predicate = idPredicate(for: item.id)

                let existingEntity = try context.fetch(request).first
                guard let entityDescription = NSEntityDescription.entity(forEntityName: "StoredRecord", in: context) else {
                    throw NSError(domain: "CoreDataRecordRepository", code: 1001, userInfo: [
                        NSLocalizedDescriptionKey: "StoredRecord entity not found in managed object model."
                    ])
                }
                let entity: NSManagedObject
                if let existingEntity {
                    entity = existingEntity
                    print("CoreDataRecordRepository.save: entity existing for id=\(item.id.uuidString)")
                } else {
                    entity = NSManagedObject(entity: entityDescription, insertInto: context)
                    print("CoreDataRecordRepository.save: entity new for id=\(item.id.uuidString)")
                }

                entity.setValue(item.id, forKey: "id")
                entity.setValue(item.createdAt, forKey: "createdAt")
                entity.setValue(Date(), forKey: "updatedAt")
                entity.setValue(item.imagePath, forKey: "imagePath")
                entity.setValue(item.correctedCropPath, forKey: "correctedCropPath")
                entity.setValue(item.rawOCRText, forKey: "rawOCRText")
                entity.setValue(RecordItem.normalizedArtistIndex(item.editableFields.artist, fallbackArtist: item.selectedDiscogsMatch?.artist ?? item.confirmedDiscogsSummary?.artist), forKey: "artistIndex")
                entity.setValue(try encode(item.ocrBoxes), forKey: "ocrBoxes")
                entity.setValue(try encode(item.selectedTitleBoxIDs), forKey: "selectedTitleBoxIDs")
                entity.setValue(try encode(item.selectedArtistBoxIDs), forKey: "selectedArtistBoxIDs")
                entity.setValue(try encode(item.selectedCatalogBoxIDs), forKey: "selectedCatalogBoxIDs")
                entity.setValue(try encode(item.editableFields), forKey: "editableFields")
                entity.setValue(try encode(item.queryHistory), forKey: "queryHistory")
                entity.setValue(try encode(item.latestCandidates), forKey: "latestCandidates")
                entity.setValue(try encode(item.selectedDiscogsMatch), forKey: "selectedMatch")
                entity.setValue(try encode(item.confirmedDiscogsSummary), forKey: "confirmedDiscogsSummary")
                entity.setValue(try encode(item.confirmedDiscogsRelease), forKey: "confirmedDiscogsRelease")
                entity.setValue(item.unresolved, forKey: "unresolved")
                entity.setValue(try encode(item.tags), forKey: "tags")

                print("CoreDataRecordRepository.save: id=\(item.id.uuidString)")
                print("CoreDataRecordRepository.save: destination=\(item.unresolved ? "Unresolved" : "Saved")")
                print("CoreDataRecordRepository.save: artist=\(item.editableFields.artist)")
                print("CoreDataRecordRepository.save: context hasChanges before save=\(context.hasChanges)")
                if context.hasChanges {
                    try context.save()
                    print("CoreDataRecordRepository.save: context.save() succeeded id=\(item.id.uuidString)")
                    context.processPendingChanges()
                } else {
                    print("CoreDataRecordRepository.save: no changes to save id=\(item.id.uuidString)")
                }
            } catch {
                saveError = error
            }
        }

        if let saveError {
            throw saveError
        }

        let fetchedByID = try fetch(id: item.id)
        print("CoreDataRecordRepository.save: post-save fetch(id:) found=\(fetchedByID != nil) id=\(item.id.uuidString)")
        let destinationItems = try fetchAll(unresolvedOnly: item.unresolved)
        print("CoreDataRecordRepository.save: post-save fetchAll(unresolvedOnly: \(item.unresolved)) count=\(destinationItems.count)")
        if fetchedByID != nil {
            NotificationCenter.default.post(name: .recordRepositoryDidChange, object: nil)
        } else {
            logger.error("Save verification failed for id=\(item.id.uuidString); change notification suppressed.")
        }
    }

    func fetchAll(unresolvedOnly: Bool) throws -> [RecordItem] {
        let context = stack.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "StoredRecord")

        request.predicate = NSPredicate(
            format: "unresolved == %@",
            NSNumber(value: unresolvedOnly)
        )

        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let records = try context.fetch(request).compactMap(mapManagedObject)
        print("CoreDataRecordRepository.fetchAll: unresolvedOnly=\(unresolvedOnly), count=\(records.count)")
        return records
    }

    func fetch(id: UUID) throws -> RecordItem? {
        let context = stack.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "StoredRecord")
        request.fetchLimit = 1
        request.predicate = idPredicate(for: id)

        let result = try context.fetch(request).first.flatMap(mapManagedObject)
        print("CoreDataRecordRepository.fetch: id=\(id.uuidString), found=\(result != nil)")
        return result
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
            let id = uuidValue(object.value(forKey: "id")),
            let createdAt = dateValue(object.value(forKey: "createdAt")),
            let updatedAt = dateValue(object.value(forKey: "updatedAt")),
            let imagePath = stringValue(object.value(forKey: "imagePath")),
            let rawOCRText = stringValue(object.value(forKey: "rawOCRText"))
        else {
            return nil
        }

        let selectedMatch: DiscogsCandidate? = decode(object.value(forKey: "selectedMatch") as? Data, fallback: Optional<DiscogsCandidate>.none)
        let editableFields: EditableFields = decode(object.value(forKey: "editableFields") as? Data, fallback: .empty)
        let persistedArtistIndex = (object.value(forKey: "artistIndex") as? String) ?? ""
        let normalizedArtistIndex = RecordItem.normalizedArtistIndex(
            persistedArtistIndex,
            fallbackArtist: editableFields.artist.isEmpty ? selectedMatch?.artist : editableFields.artist
        )

        return RecordItem(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            imagePath: imagePath,
            correctedCropPath: stringValue(object.value(forKey: "correctedCropPath")),
            rawOCRText: rawOCRText,
            ocrBoxes: decode(object.value(forKey: "ocrBoxes") as? Data, fallback: []),
            selectedTitleBoxIDs: decode(object.value(forKey: "selectedTitleBoxIDs") as? Data, fallback: []),
            selectedArtistBoxIDs: decode(object.value(forKey: "selectedArtistBoxIDs") as? Data, fallback: []),
            selectedCatalogBoxIDs: decode(object.value(forKey: "selectedCatalogBoxIDs") as? Data, fallback: []),
            editableFields: editableFields,
            artistIndex: normalizedArtistIndex,
            queryHistory: decode(object.value(forKey: "queryHistory") as? Data, fallback: []),
            latestCandidates: decode(object.value(forKey: "latestCandidates") as? Data, fallback: []),
            selectedDiscogsMatch: selectedMatch,
            confirmedDiscogsSummary: decode(object.value(forKey: "confirmedDiscogsSummary") as? Data, fallback: selectedMatch.map(DiscogsReleaseSummary.init(candidate:))),
            confirmedDiscogsRelease: decode(object.value(forKey: "confirmedDiscogsRelease") as? Data, fallback: Optional<DiscogsReleaseDetails>.none),
            unresolved: object.value(forKey: "unresolved") as? Bool ?? true,
            tags: decode(object.value(forKey: "tags") as? Data, fallback: [])
        )
    }

    private func idPredicate(for id: UUID) -> NSPredicate {
        NSPredicate(format: "id == %@", id as NSUUID)
    }

    private func uuidValue(_ value: Any?) -> UUID? {
        if let uuid = value as? UUID {
            return uuid
        }

        if let uuid = value as? NSUUID {
            return UUID(uuidString: uuid.uuidString)
        }

        if let string = value as? String {
            return UUID(uuidString: string)
        }

        return nil
    }

    private func dateValue(_ value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }

        if let date = value as? NSDate {
            return date as Date
        }

        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }

        if let string = value as? NSString {
            return string as String
        }

        return nil
    }
}
