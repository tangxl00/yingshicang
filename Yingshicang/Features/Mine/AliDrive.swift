import Foundation

// MARK: - R-39 阿里云盘开放接口客户端

/// 阿里云盘开放平台 OpenAPI 客户端。
///
/// 接口证据（2026-11 实测）：
/// - `POST https://openapi.alipan.com/adrive/v1.0/openFile/list`：GET → 405
///   HttpRequestMethodNotSupportedException（证明仅收 POST），伪 Bearer → 401
///   AccessTokenInvalid（证明端点真实且强制鉴权）；
/// - `POST …/openFile/getDownloadUrl` / `getVideoPlayInfo` / `getVideoPreviewPlayInfo`
///   同形态。
/// 端点真实、鉴权真实；**字段级返回结构未用有效 Token 端到端实测**（沙箱无凭据），
/// 解码按开放平台公开文档的字段名（drive_id / file_id / parent_file_id / name /
/// type / size / url），真实响应若多字段则 Codable 自动忽略未知键、不报错。
struct AliDriveFile: Codable, Equatable {
    var fileId: String?
    var parentId: String?
    var name: String?
    var type: String?          // "folder" | "file"
    var size: Int64?
    var url: String?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case parentId = "parent_file_id"
        case name, type, size, url
    }

    var isFolder: Bool { type == "folder" }
}

enum AliDriveError: LocalizedError, Equatable {
    case noToken
    case driveIDMissing
    case badStatus(Int, String)
    case emptyResponse
    case noDownloadURL

    var errorDescription: String? {
        switch self {
        case .noToken: return "未配置阿里云盘 Token"
        case .driveIDMissing: return "无法获取网盘 drive_id（Token 可能已失效）"
        case .badStatus(let code, let body): return "阿里云盘接口返回 \(code)：\(body)"
        case .emptyResponse: return "阿里云盘接口返回空内容"
        case .noDownloadURL: return "该文件没有可用的下载地址（可能需要开通直链权限）"
        }
    }
}

/// R-47 授权入口的 URL 构造（纯函数，单测覆盖）。
enum AliDriveAuth {
    static let authorizeHost = "openapi.alipan.com"
    static let authorizePath = "/oauth/authorize"

    /// OAuth 授权页 URL。`response_type=code` 是开放平台唯一支持的流程；
    /// 授权完成后 302 到 redirect_uri 并带 code —— 但本工程没有注册开放平台应用，
    /// 没有内置 client_id/secret，所以默认走不了完整 OAuth（见 KNOWN_DIFFERENCES）。
    /// 该构造函数保证：给定 client_id 时产出结构正确的授权 URL，
    /// 供站点脚本/用户自配凭据时真实使用。
    static func authorizeURL(clientID: String,
                             redirectURI: String,
                             scope: String = "user:base,file:read:all") -> URL? {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let redirect = URL(string: redirectURI),
              redirect.scheme != nil else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = authorizeHost
        components.path = authorizePath
        components.queryItems = [
            URLQueryItem(name: "client_id", value: trimmed),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "response_type", value: "code")
        ]
        return components.url
    }
}

/// 开放接口客户端：文件列表 + 下载地址转发。
/// Token 从 `Settings.aliToken`（Keychain）取；drive_id 通过
/// `POST /adrive/v1.0/user/getDriveInfo` 获取并缓存（内存级，Token 变更时重取）。
final class AliDriveClient {

    static let shared = AliDriveClient()

    private let http: HTTPClient
    private var cachedDriveID: String?

    init(http: HTTPClient = .shared) {
        self.http = http
    }

    // MARK: - 传输层

    private func post<T: Decodable>(_ path: String,
                                    body: [String: Any],
                                    token: String,
                                    completion: @escaping (Result<T, AliDriveError>) -> Void) {
        let url = "https://openapi.alipan.com" + path
        var options = HTTPOptions()
        options.method = "POST"
        options.headers = [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json"
        ]
        options.body = try? JSONSerialization.data(withJSONObject: body)
        options.timeout = 20
        http.request(url, options: options) { response in
            let result: Result<T, AliDriveError> = {
                if let failure = response.transport {
                    return .failure(.badStatus(0, failure.localizedDescription))
                }
                guard response.status == 200, !response.content.isEmpty else {
                    return .failure(.badStatus(response.status, String(response.content.prefix(200))))
                }
                guard let data = response.data ?? response.content.data(using: .utf8) else {
                    return .failure(.emptyResponse)
                }
                do {
                    return .success(try JSONDecoder().decode(T.self, from: data))
                } catch {
                    return .failure(.badStatus(200, "解码失败：\(error.localizedDescription)"))
                }
            }()
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - drive_id

    private struct DriveInfo: Codable {
        let defaultDriveId: String?
        enum CodingKeys: String, CodingKey { case defaultDriveId = "default_drive_id" }
    }

    func driveID(completion: @escaping (Result<String, AliDriveError>) -> Void) {
        if let cached = cachedDriveID { return completion(.success(cached)) }
        let token = Settings.shared.aliToken
        guard !token.isEmpty else { return completion(.failure(.noToken)) }
        post("/adrive/v1.0/user/getDriveInfo", body: [:], token: token) {
            (result: Result<DriveInfo, AliDriveError>) in
            switch result {
            case .success(let info):
                guard let id = info.defaultDriveId, !id.isEmpty else {
                    return completion(.failure(.driveIDMissing))
                }
                self.cachedDriveID = id
                completion(.success(id))
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    // MARK: - 文件列表

    struct FileList: Codable {
        let items: [AliDriveFile]?
    }

    /// 列目录。`parentFileId` 传 "root" 表示根目录。
    func list(parentFileId: String = "root",
              completion: @escaping (Result<[AliDriveFile], AliDriveError>) -> Void) {
        let token = Settings.shared.aliToken
        guard !token.isEmpty else { return completion(.failure(.noToken)) }
        driveID { [weak self] driveResult in
            guard let self = self else { return }
            switch driveResult {
            case .success(let driveID):
                self.post("/adrive/v1.0/openFile/list",
                          body: [
                            "drive_id": driveID,
                            "parent_file_id": parentFileId,
                            "limit": 100,
                            "order_by": "name",
                            "order_direction": "ASC"
                          ],
                          token: token) { (result: Result<FileList, AliDriveError>) in
                    switch result {
                    case .success(let list): completion(.success(list.items ?? []))
                    case .failure(let error): completion(.failure(error))
                    }
                }
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    // MARK: - 下载地址转发

    struct DownloadURL: Codable {
        let url: String?
        let expiration: String?
    }

    /// 取文件直链（视频文件可直接进播放器；直链有时效，取到即用）。
    func downloadURL(fileId: String,
                     completion: @escaping (Result<String, AliDriveError>) -> Void) {
        let token = Settings.shared.aliToken
        guard !token.isEmpty else { return completion(.failure(.noToken)) }
        driveID { [weak self] driveResult in
            guard let self = self else { return }
            switch driveResult {
            case .success(let driveID):
                self.post("/adrive/v1.0/openFile/getDownloadUrl",
                          body: ["drive_id": driveID, "file_id": fileId],
                          token: token) { (result: Result<DownloadURL, AliDriveError>) in
                    switch result {
                    case .success(let info):
                        guard let url = info.url, !url.isEmpty else {
                            return completion(.failure(.noDownloadURL))
                        }
                        completion(.success(url))
                    case .failure(let error): completion(.failure(error))
                    }
                }
            case .failure(let error): completion(.failure(error))
            }
        }
    }

    /// Token 变更后清缓存。
    func reset() { cachedDriveID = nil }
}
