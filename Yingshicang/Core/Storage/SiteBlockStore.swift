import Foundation
import GRDB

/// 屏蔽源（R-09 指定搜索源的开关状态）。
/// 语义：被屏蔽的站点不参与全局搜索/快搜，仍可在首页分类里浏览（与原 App 一致）。
final class SiteBlockStore {
    static let shared = SiteBlockStore()

    private var db: DatabaseQueue? { AppDatabase.shared.dbQueue }
    private var memory: Set<String> = []

    func blockedKeys() -> Set<String> {
        guard let db = db else { return memory }
        let keys = (try? db.read { try BlockedSiteRecord.fetchAll($0).map { $0.siteKey } }) ?? []
        return Set(keys)
    }

    func isBlocked(_ key: String) -> Bool { blockedKeys().contains(key) }

    func setBlocked(_ key: String, blocked: Bool) {
        if let db = db {
            _ = try? db.write { db in
                if blocked {
                    try BlockedSiteRecord(siteKey: key).insert(db, onConflict: .ignore)
                } else {
                    try BlockedSiteRecord.filter(Column("siteKey") == key).deleteAll(db)
                }
            }
        } else {
            if blocked { memory.insert(key) } else { memory.remove(key) }
        }
    }

    func setAll(_ keys: [String], blocked: Bool) {
        for key in keys { setBlocked(key, blocked: blocked) }
    }
}
