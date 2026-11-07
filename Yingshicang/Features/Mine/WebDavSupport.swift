import Foundation

/// R-28 本地配置导入：把用户通过文件 App 选中的配置文本解析并落库。
///
/// 与网络加载（ConfigRepository.load）的区别：不走 HTTP，直接解析文本 → store，
/// 全程无网络依赖，可单测覆盖。sourceURL 记录导入来源名（非真实 URL，
/// 快照语义与网络加载一致）。
enum LocalConfigImporter {

    /// 导入一段配置文本。成功时已写入 ConfigRepository（内存 + 快照）。
    static func importConfig(text: String, sourceName: String) -> Result<ConfigBundle, String> {
        switch ConfigParser.parseResult(text: text) {
        case .success(let bundle):
            ConfigRepository.shared.store(bundle: bundle, sourceURL: sourceName)
            return .success(bundle)
        case .failure(let failure):
            return .failure(failure.message)
        }
    }
}

/// R-45 WebDAV 连接测试：PROPFIND 深度 0 探测服务器可达性与凭据有效性。
///
/// 判定口径（对齐 WebDAV 规范与主流服务端行为）：
/// - 207 Multi-Status / 200：连接且凭据有效
/// - 401 / 403：服务器可达，但凭据无效
/// - 404：路径不存在（服务器可达，地址配错）
/// - 405：可达但不是 WebDAV（PUT/PROPFIND 不支持）
/// - status 0（传输层失败）：网络不可达 / TLS 错误，透出原始 NSURLError 描述
enum WebDavConnectionTester {

    /// 探测结果（可测试的纯语义分类，UI 只负责展示文案）。
    enum Outcome: Equatable {
        case ok
        case unauthorized
        case notFound
        case notWebDav
        case transport(String)

        /// 面向用户的一行文案。
        var displayText: String {
            switch self {
            case .ok: return "连接成功，凭据有效"
            case .unauthorized: return "服务器可达，但账号或密码无效"
            case .notFound: return "服务器可达，但该路径不存在"
            case .notWebDav: return "服务器可达，但不是 WebDAV 服务"
            case .transport(let detail): return "无法连接：\(detail)"
            }
        }

        /// 由 HTTP 响应归类（纯函数，单测直接覆盖各状态码分支）。
        static func classify(status: Int, transport: TransportFailure?) -> Outcome {
            if let transport = transport { return .transport(transport.displayText) }
            switch status {
            case 200...299: return .ok
            case 401, 403: return .unauthorized
            case 404: return .notFound
            case 405: return .notWebDav
            default: return .notWebDav
            }
        }
    }

    /// 服务器地址归一化：去首尾空白、去全部尾部斜杠（拼接备份文件名时不会出现双斜杠）。
    static func normalizedBase(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed = String(trimmed.dropLast())
        }
        return trimmed
    }

    /// 备份文件完整地址：base + 固定文件名（可测试的纯拼接）。
    static func backupFileURL(base: String) -> String {
        let normalized = normalizedBase(base)
        guard !normalized.isEmpty else { return "" }
        return normalized + "/yingshicang-backup.json"
    }

    /// Basic 认证头（纯函数，单测断言 base64 编码）。
    static func basicAuthorization(account: String, password: String) -> String {
        let raw = "\(account):\(password)"
        return "Basic " + Data(raw.utf8).base64EncodedString()
    }

    /// 发起 PROPFIND 深度 0 探测。completion 在主线程。
    static func testConnection(base: String,
                               account: String,
                               password: String,
                               completion: @escaping (Outcome) -> Void) {
        let url = normalizedBase(base)
        guard !url.isEmpty else {
            DispatchQueue.main.async { completion(.transport("服务器地址为空")) }
            return
        }
        var options = HTTPOptions()
        options.method = "PROPFIND"
        options.headers = [
            "Depth": "0",
            "Authorization": basicAuthorization(account: account, password: password)
        ]
        HTTPClient.shared.request(url, options: options) { response in
            let outcome = Outcome.classify(status: response.status, transport: response.transport)
            DispatchQueue.main.async { completion(outcome) }
        }
    }
}

/// R-46 备份包：历史 + 收藏 + 屏蔽源打包成一份 JSON，经 WebDAV 上传/下载。
///
/// 结构对齐原 APK 的备份语义（本地数据整体搬运），字段名自定（原格式无公开文档）。
struct BackupPayload: Codable, Equatable {
    var version: Int
    var exportedAt: Double
    var history: [HistoryRecord]
    var favorites: [FavoriteRecord]
    var blockedSites: [String]

    init(version: Int = 1,
         exportedAt: Double = Date().timeIntervalSince1970,
         history: [HistoryRecord] = HistoryStore.shared.all(),
         favorites: [FavoriteRecord] = FavoriteStore.shared.all(),
         blockedSites: [String] = []) {
        self.version = version
        self.exportedAt = exportedAt
        self.history = history
        self.favorites = favorites
        self.blockedSites = blockedSites
    }

    /// 从当前各 Store 收集（上传前调用）。
    static func make() -> BackupPayload {
        BackupPayload(blockedSites: Array(SiteBlockStore.shared.blockedKeys()))
    }

    /// 恢复：历史/收藏 upsert 回库（保留较新记录语义由 upsert 决定），屏蔽源恢复。
    func restore() {
        for record in history {
            HistoryStore.shared.upsert(record: HistoryRecord(
                siteKey: record.siteKey, vodId: record.vodId, vodName: record.vodName,
                vodPic: record.vodPic, flag: record.flag, playIndex: record.playIndex,
                episodeIndex: record.episodeIndex, position: record.position,
                duration: record.duration, updatedAt: record.updatedAt, finished: record.finished))
        }
        for favorite in favorites {
            if !FavoriteStore.shared.isFavorite(siteKey: favorite.siteKey, vodId: favorite.vodId) {
                FavoriteStore.shared.toggle(siteKey: favorite.siteKey, vodId: favorite.vodId,
                                            vodName: favorite.vodName, vodPic: favorite.vodPic)
            }
        }
        for key in blockedSites {
            SiteBlockStore.shared.setBlocked(key, blocked: true)
        }
    }

    /// 编码为 JSON 文本（上传内容，纯函数可测）。
    static func encodeJSON(_ payload: BackupPayload) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 从 JSON 文本解码（下载内容，纯函数可测；坏文本返回 nil）。
    static func decodeJSON(_ text: String) -> BackupPayload? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BackupPayload.self, from: data)
    }
}

/// R-46 备份传输：WebDAV PUT / GET 备份文件。completion 在主线程。
enum BackupTransfer {

    enum TransferError: Equatable {
        case emptyCredentials
        case upload(String)
        case download(String)
        case noBackupFile

        var displayText: String {
            switch self {
            case .emptyCredentials: return "请先在 WebDAV 设置中填写服务器与账号"
            case .upload(let detail): return "上传失败：\(detail)"
            case .download(let detail): return "下载失败：\(detail)"
            case .noBackupFile: return "服务器上还没有备份文件"
            }
        }
    }

    /// 上传当前数据为备份文件。
    static func upload(completion: @escaping (Result<Double, TransferError>) -> Void) {
        let base = Settings.shared.webDavURL
        let account = Settings.shared.webDavAccount
        let password = Settings.shared.webDavPassword
        guard !WebDavConnectionTester.normalizedBase(base).isEmpty, !account.isEmpty else {
            DispatchQueue.main.async { completion(.failure(.emptyCredentials)) }
            return
        }
        let payload = BackupPayload.make()
        guard let json = BackupPayload.encodeJSON(payload) else {
            DispatchQueue.main.async { completion(.failure(.upload("本地数据打包失败"))) }
            return
        }
        var options = HTTPOptions()
        options.method = "PUT"
        options.headers = ["Authorization": WebDavConnectionTester.basicAuthorization(account: account, password: password)]
        options.body = Data(json.utf8)
        let url = WebDavConnectionTester.backupFileURL(base: base)
        HTTPClient.shared.request(url, options: options) { response in
            DispatchQueue.main.async {
                if response.ok {
                    completion(.success(payload.exportedAt))
                } else {
                    completion(.failure(.upload("HTTP \(response.status)")))
                }
            }
        }
    }

    /// 下载备份文件并恢复。
    static func downloadAndRestore(completion: @escaping (Result<BackupPayload, TransferError>) -> Void) {
        let base = Settings.shared.webDavURL
        let account = Settings.shared.webDavAccount
        let password = Settings.shared.webDavPassword
        guard !WebDavConnectionTester.normalizedBase(base).isEmpty, !account.isEmpty else {
            DispatchQueue.main.async { completion(.failure(.emptyCredentials)) }
            return
        }
        var options = HTTPOptions()
        options.headers = ["Authorization": WebDavConnectionTester.basicAuthorization(account: account, password: password)]
        let url = WebDavConnectionTester.backupFileURL(base: base)
        HTTPClient.shared.request(url, options: options) { response in
            DispatchQueue.main.async {
                if !response.ok {
                    if response.status == 404 {
                        completion(.failure(.noBackupFile))
                    } else {
                        completion(.failure(.download("HTTP \(response.status)")))
                    }
                    return
                }
                if response.content.isEmpty {
                    completion(.failure(.noBackupFile))
                    return
                }
                guard let payload = BackupPayload.decodeJSON(response.content) else {
                    completion(.failure(.download("备份文件格式无法解析")))
                    return
                }
                payload.restore()
                completion(.success(payload))
            }
        }
    }
}
