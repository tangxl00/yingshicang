import Foundation
import GRDB

/// 收藏服务。所有写操作异步落到 GRDB；读操作同步（列表规模小，同步足够快）。
final class FavoriteStore {
    static let shared = FavoriteStore()

    private var db: DatabaseQueue? { AppDatabase.shared.dbQueue }
    private var memoryFallback: [FavoriteRecord] = []

    func all() -> [FavoriteRecord] {
        guard let db = db else { return memoryFallback }
        return (try? db.read { try FavoriteRecord.order(Column("createdAt").desc).fetchAll($0) }) ?? []
    }

    func isFavorite(siteKey: String, vodId: String) -> Bool {
        guard let db = db else { return memoryFallback.contains { $0.siteKey == siteKey && $0.vodId == vodId } }
        return (try? db.read { db in
            try FavoriteRecord.filter(Column("siteKey") == siteKey && Column("vodId") == vodId).fetchCount(db) > 0
        }) ?? false
    }

    /// 切换收藏态，返回切换后的状态（true = 已收藏）。
    @discardableResult
    func toggle(siteKey: String, vodId: String, vodName: String, vodPic: String) -> Bool {
        if isFavorite(siteKey: siteKey, vodId: vodId) {
            remove(siteKey: siteKey, vodId: vodId)
            return false
        }
        let record = FavoriteRecord(siteKey: siteKey, vodId: vodId, vodName: vodName, vodPic: vodPic)
        if let db = db {
            try? db.write { try record.insert($0, onConflict: .replace) }
        } else {
            memoryFallback.insert(record, at: 0)
        }
        return true
    }

    func remove(siteKey: String, vodId: String) {
        if let db = db {
            _ = try? db.write { db in
                try FavoriteRecord.filter(Column("siteKey") == siteKey && Column("vodId") == vodId).deleteAll(db)
            }
        } else {
            memoryFallback.removeAll { $0.siteKey == siteKey && $0.vodId == vodId }
        }
    }

    func removeAll() {
        if let db = db { _ = try? db.write { try FavoriteRecord.deleteAll($0) } }
        memoryFallback.removeAll()
    }
}
