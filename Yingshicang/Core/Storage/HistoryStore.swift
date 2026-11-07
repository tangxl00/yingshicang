import Foundation
import GRDB

/// 播放历史服务。
///
/// 「历史记录合并」开关（R-30 第 3 项）：
/// - 开启：同一片名只保留最新一条（不同源的同名片合并）
/// - 关闭：按 (站点, vodId) 分别保留
final class HistoryStore {
    static let shared = HistoryStore()

    private var db: DatabaseQueue? { AppDatabase.shared.dbQueue }
    private var memoryFallback: [HistoryRecord] = []

    /// 最近一条（R-24 底部悬浮播放记录条）。
    func latest() -> HistoryRecord? {
        guard let db = db else { return memoryFallback.max { $0.updatedAt < $1.updatedAt } }
        return try? db.read { try HistoryRecord.order(Column("updatedAt").desc).fetchOne($0) }
    }

    func all() -> [HistoryRecord] {
        guard let db = db else { return memoryFallback.sorted { $0.updatedAt > $1.updatedAt } }
        return (try? db.read { try HistoryRecord.order(Column("updatedAt").desc).fetchAll($0) }) ?? []
    }

    /// 续播定位（R-22 点卡片带进度续播）。
    func resume(siteKey: String, vodId: String) -> HistoryRecord? {
        guard let db = db else { return memoryFallback.first { $0.siteKey == siteKey && $0.vodId == vodId } }
        return try? db.read { db in
            try HistoryRecord.filter(Column("siteKey") == siteKey && Column("vodId") == vodId).fetchOne(db)
        }
    }

    func upsert(record: HistoryRecord) {
        guard let db = db else {
            memoryFallback.removeAll { $0.siteKey == record.siteKey && $0.vodId == record.vodId }
            memoryFallback.append(record)
            return
        }
        try? db.write { db in
            // 合并开关打开时，先按片名删掉其它源的同一部片。
            if Settings.shared.historyMerge {
                try HistoryRecord.filter(Column("vodName") == record.vodName).deleteAll(db)
            }
            try record.save(db, onConflict: .replace)
        }
    }

    func remove(id: Int64) {
        if let db = db {
            _ = try? db.write { try HistoryRecord.filter(Column("id") == id).deleteAll($0) }
        } else {
            memoryFallback.removeAll { $0.id == id }
        }
    }

    func removeAll() {
        if let db = db { _ = try? db.write { try HistoryRecord.deleteAll($0) } }
        memoryFallback.removeAll()
    }
}
