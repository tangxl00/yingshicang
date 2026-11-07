import Foundation
import GRDB

/// 收藏记录。
struct FavoriteRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "favorite"
    var id: Int64?
    var siteKey: String
    var vodId: String
    var vodName: String
    var vodPic: String
    var createdAt: Double

    init(id: Int64? = nil, siteKey: String, vodId: String, vodName: String, vodPic: String, createdAt: Double = Date().timeIntervalSince1970) {
        self.id = id
        self.siteKey = siteKey
        self.vodId = vodId
        self.vodName = vodName
        self.vodPic = vodPic
        self.createdAt = createdAt
    }

    func didInsert(_ inserted: InsertionSuccess) { }
}

/// 历史记录。「历史记录合并」开关打开时按播出片名合并（见 HistoryStore）。
struct HistoryRecord: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "history"
    var id: Int64?
    var siteKey: String
    var vodId: String
    var vodName: String
    var vodPic: String
    var flag: String
    var playIndex: Int
    var episodeIndex: Int
    var position: Double
    var duration: Double
    var updatedAt: Double
    var finished: Bool

    init(id: Int64? = nil, siteKey: String, vodId: String, vodName: String, vodPic: String,
         flag: String, playIndex: Int, episodeIndex: Int, position: Double, duration: Double,
         updatedAt: Double = Date().timeIntervalSince1970, finished: Bool = false) {
        self.id = id
        self.siteKey = siteKey
        self.vodId = vodId
        self.vodName = vodName
        self.vodPic = vodPic
        self.flag = flag
        self.playIndex = playIndex
        self.episodeIndex = episodeIndex
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
        self.finished = finished
    }
}

struct LanDeviceRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "lanDevice"
    var id: Int64?
    var name: String
    var ip: String
    var createdAt: Double

    init(id: Int64? = nil, name: String, ip: String, createdAt: Double = Date().timeIntervalSince1970) {
        self.id = id
        self.name = name
        self.ip = ip
        self.createdAt = createdAt
    }
}

struct BlockedSiteRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "blockedSite"
    var id: Int64?
    var siteKey: String

    init(id: Int64? = nil, siteKey: String) {
        self.id = id
        self.siteKey = siteKey
    }
}
