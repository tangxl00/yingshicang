import Foundation
import GRDB

/// GRDB 数据库封装。选 GRDB 的原因见架构文档：对齐原 App 的 Room 关系型模型，
/// 收藏/历史/局域网设备/屏蔽源都是结构化记录，用 SQLite 比 JSON 文件更利于排序与合并查询。
///
/// 迁移策略：v1 建表，后续版本只追加 migration，绝不修改已执行的 migration。
final class AppDatabase {
    static let shared = AppDatabase()

    private(set) var dbQueue: DatabaseQueue?

    private init() {}

    /// 在 App 启动早期调用。失败时置 nil，上层走内存兜底（不 crash）。
    func setup() {
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true)
                .appendingPathComponent("Yingshicang", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let dbURL = folder.appendingPathComponent("yingshicang.sqlite")
            let queue = try DatabaseQueue(path: dbURL.path)
            try migrator.migrate(queue)
            dbQueue = queue
            Log.info("[DB] ready at \(dbURL.lastPathComponent)")
        } catch {
            Log.error("[DB] setup failed: \(error)")
            dbQueue = nil
        }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            // 收藏表。字段依据 R-23 列表所需：片名/海报/来源站点/vod id/加入时间。
            // 文档 4.1 将字段名标为「待确认」，此处按语义定名并列入默认取值清单。
            try db.create(table: "favorite") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("siteKey", .text).notNull()
                t.column("vodId", .text).notNull()
                t.column("vodName", .text).notNull()
                t.column("vodPic", .text).notNull().defaults(to: "")
                t.column("createdAt", .double).notNull()
                t.uniqueKey(["siteKey", "vodId"])
            }
            // 历史表。字段依据 R-22/R-24：片名/海报/线路/集数/进度秒/更新时间/是否完结。
            try db.create(table: "history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("siteKey", .text).notNull()
                t.column("vodId", .text).notNull()
                t.column("vodName", .text).notNull()
                t.column("vodPic", .text).notNull().defaults(to: "")
                t.column("flag", .text).notNull().defaults(to: "")
                t.column("playIndex", .integer).notNull().defaults(to: 0)
                t.column("episodeIndex", .integer).notNull().defaults(to: 0)
                t.column("position", .double).notNull().defaults(to: 0)
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("updatedAt", .double).notNull()
                t.column("finished", .boolean).notNull().defaults(to: false)
                // 合并开关打开时，同一片只留一条；默认按 (siteKey, vodId) 唯一。
                t.uniqueKey(["siteKey", "vodId"])
            }
            // 局域网设备表：设备名 + IP（R-43 两个输入框直接反证）。
            try db.create(table: "lanDevice") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("ip", .text).notNull()
                t.column("createdAt", .double).notNull()
            }
            // 屏蔽源表：站点 key 的启用/禁用（R-09 开关列表）。
            try db.create(table: "blockedSite") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("siteKey", .text).notNull().unique()
            }
        }
        return migrator
    }
}
