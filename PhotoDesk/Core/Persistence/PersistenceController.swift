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
        let expiresAtAttr = attribute("expiresAt", .dateAttributeType, optional: false)
        actionLog.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("kind", .stringAttributeType, optional: false, defaultValue: ""),
            attribute("assetIDsJSON", .stringAttributeType, optional: false, defaultValue: "[]"),
            attribute("prevStateJSON", .stringAttributeType, optional: true),
            attribute("toastText", .stringAttributeType, optional: false, defaultValue: ""),
            attribute("createdAt", .dateAttributeType, optional: false),
            expiresAtAttr,
            attribute("isUndone", .booleanAttributeType, optional: false, defaultValue: false),
            attribute("undoKindRaw", .stringAttributeType, optional: true),
        ]
        // 索引：expiresAt（docs/03 §4.2）
        actionLog.indexes = [makeIndex(name: "idx_expiresAt", property: expiresAtAttr)]

        // TrashItem：撤销保险副本索引（非备份）
        let trashItem = NSEntityDescription()
        trashItem.name = "TrashItem"
        trashItem.managedObjectClassName = "NSManagedObject"
        let createdAtAttr = attribute("createdAt", .dateAttributeType, optional: false)
        trashItem.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("originLocalID", .stringAttributeType, optional: false),
            attribute("fileRelativePath", .stringAttributeType, optional: false),
            attribute("mediaType", .integer16AttributeType, optional: false, defaultValue: 0),
            attribute("byteSize", .integer64AttributeType, optional: false, defaultValue: 0),
            attribute("metaJSON", .stringAttributeType, optional: false, defaultValue: "{}"),
            createdAtAttr,
        ]
        trashItem.indexes = [makeIndex(name: "idx_createdAt", property: createdAtAttr)]

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

    private static func makeIndex(name: String, property: NSPropertyDescription) -> NSFetchIndexDescription {
        let element = NSFetchIndexElementDescription(property: property, collationType: .binary)
        return NSFetchIndexDescription(name: name, elements: [element])
    }

    // MARK: - 便捷存取

    /// 后台写（新建/更新/删除 NSManagedObject 的统一入口）
    func performBackground(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask(block)
    }

    /// 元数据小行的同步写（撤销栈/副本索引等；写完即可读，消除后台合并竞态。
    /// 仅限低频小数据——照片流数据不走 Core Data）
    func performSync(_ block: (NSManagedObjectContext) -> Void) {
        container.viewContext.performAndWait {
            block(container.viewContext)
        }
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }
}
