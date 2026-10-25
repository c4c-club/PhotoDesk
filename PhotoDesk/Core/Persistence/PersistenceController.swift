// MARK: - 职责说明：Core Data 栈（docs/03 §4.2）——
// 模型采用程序化 NSManagedObjectModel（与 .xcdatamodeld 等价，且便于无 Xcode 环境维护；字段与文档一一对应）。
// 实体：ActionLog（撤销栈持久化，P3）/ TrashItem（撤销保险副本索引，P3）；
//       Fingerprint / DuplicateGroup / ScanSession / OCRText 随 M4/M5 增补。
// 写走 backgroundContext（performBackgroundTask），主线程只读 viewContext（AGENTS.md §3.5）；
// 无 App Groups，库放默认沙盒（docs/06 §4.1）。

import CoreData
import Foundation

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    /// 测试可注入内存存储
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "PhotoDesk", managedObjectModel: Self.makeModel())
        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        }
        container.loadPersistentStores { _, error in
            if let error {
                // 存储损坏不可恢复场景：删除重建（首版轻量策略；迁移随 M9 完善）
                assertionFailure("Core Data 加载失败: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - 实体（字段对齐 docs/03 §4.2）

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // ActionLog：撤销栈持久化
        let actionLog = NSEntityDescription()
        actionLog.name = "ActionLog"
        actionLog.managedObjectClassName = "NSManagedObject"
        actionLog.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("kind", .integer16AttributeType, optional: false, defaultValue: 0),
            attribute("assetIDsJSON", .stringAttributeType, optional: false, defaultValue: "[]"),
            attribute("prevStateJSON", .stringAttributeType, optional: true),
            attribute("toastText", .stringAttributeType, optional: false, defaultValue: ""),
            attribute("createdAt", .dateAttributeType, optional: false),
            attribute("expiresAt", .dateAttributeType, optional: false),
            attribute("isUndone", .booleanAttributeType, optional: false, defaultValue: false),
            attribute("undoKindRaw", .stringAttributeType, optional: true),
        ]
        // 索引：expiresAt（docs/03 §4.2）
        actionLog.indexes = [makeIndex("expiresAt")]

        // TrashItem：撤销保险副本索引（非备份）
        let trashItem = NSEntityDescription()
        trashItem.name = "TrashItem"
        trashItem.managedObjectClassName = "NSManagedObject"
        trashItem.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("originLocalID", .stringAttributeType, optional: false),
            attribute("fileRelativePath", .stringAttributeType, optional: false),
            attribute("mediaType", .integer16AttributeType, optional: false, defaultValue: 0),
            attribute("byteSize", .integer64AttributeType, optional: false, defaultValue: 0),
            attribute("metaJSON", .stringAttributeType, optional: false, defaultValue: "{}"),
            attribute("createdAt", .dateAttributeType, optional: false),
        ]
        trashItem.indexes = [makeIndex("createdAt")]

        model.entities = [actionLog, trashItem]
        return model
    }

    private static func attribute(_ name: String, _ type: NSAttributeType,
                                  optional: Bool, defaultValue: Any? = nil) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = name
        attr.attributeType = type
        attr.isOptional = optional
        attr.defaultValue = defaultValue
        return attr
    }

    private static func makeIndex(_ property: String) -> NSFetchIndexDescription {
        let element = NSFetchIndexElementDescription(property: property, collationType: .binary)
        return NSFetchIndexDescription(name: "idx_\(property)", elements: [element])
    }

    // MARK: - 便捷存取

    /// 后台写（新建/更新/删除 NSManagedObject 的统一入口）
    func performBackground(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask(block)
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }
}
