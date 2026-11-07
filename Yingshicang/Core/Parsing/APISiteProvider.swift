import Foundation

/// JSON API 站点（type=1，规格 4.2 节）。
///
/// 约定沿用 TVBox 系采集站的通用形态：
/// - 分类 / 首页：`<api>?ac=list&t=<分类id>&pg=<页码>`
/// - 搜索：`<api>?wd=<关键词>&pg=<页码>`
/// - 详情：`<api>?ac=detail&ids=<vodId>`
/// 当站点提供了 `url` / `searchUrl` / `detailUrl` 模板时，优先用模板，
/// 并按规格替换 `fyclass` / `fypage` / `**` 占位符。
///
/// 返回体按 `{list:[{vod_id,vod_name,vod_pic,vod_remarks}]}` 解析，
/// 字段名兼容驼峰与下划线两种写法（不同作者的配置混用）。
final class APISiteProvider: SiteProvider {
    let site: SiteConfig

    init(site: SiteConfig) { self.site = site }

    // MARK: - 网络

    private func fetch(_ urlString: String, completion: @escaping (Result<Any?, SiteError>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(.parse("接口地址无效：\(urlString)")))
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(site.timeout > 0 ? site.timeout : 15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        for (key, value) in site.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.network(-1)))
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let data = data else {
                completion(.failure(.network(code)))
                return
            }
            let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            completion(.success(object))
        }.resume()
    }

    /// 在站点 api 上追加查询参数；站点 api 自带的查询参数会保留。
    private func buildURL(_ query: [String: String]) -> String {
        guard var components = URLComponents(string: site.api) else { return site.api }
        var items = components.queryItems ?? []
        for (key, value) in query {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items
        return components.url?.absoluteString ?? site.api
    }

    /// 展开规格中的占位符：分类 id、页码、关键词。
    private func expand(_ template: String, classId: String, page: Int, keyword: String) -> String {
        var text = template
        text = text.replacingOccurrences(of: "fyclass", with: classId)
        text = text.replacingOccurrences(of: "fypage", with: String(page))
        text = text.replacingOccurrences(of: "**", with: keyword)
        return text
    }

    private func categoryURL(classId: String, page: Int) -> String {
        if !site.url.isEmpty {
            return expand(site.url, classId: classId, page: page, keyword: "")
        }
        return buildURL(["ac": "list", "t": classId, "pg": String(page)])
    }

    private func searchURL(keyword: String, page: Int) -> String {
        if !site.searchUrl.isEmpty {
            return expand(site.searchUrl, classId: "", page: page, keyword: keyword)
        }
        return buildURL(["wd": keyword, "pg": String(page)])
    }

    private func detailURL(id: String) -> String {
        if !site.detailUrl.isEmpty {
            return expand(site.detailUrl, classId: "", page: 1, keyword: id)
        }
        return buildURL(["ac": "detail", "ids": id])
    }

    // MARK: - 解析

    private static func text(_ dict: [String: Any], _ keys: [String]) -> String {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
            if let value = dict[key] as? NSNumber { return value.stringValue }
        }
        return ""
    }

    /// 从返回体里取出 vod 列表，兼容 `[...]` 与 `{list:[...]}` / `{data:{list:[...]}}`。
    private func vodItems(from object: Any?) -> [VodItem] {
        var array: [Any] = []
        if let list = object as? [Any] {
            array = list
        } else if let dict = object as? [String: Any] {
            if let list = dict["list"] as? [Any] {
                array = list
            } else if let data = dict["data"] as? [String: Any], let list = data["list"] as? [Any] {
                array = list
            } else if let data = dict["data"] as? [Any] {
                array = data
            }
        }
        var items: [VodItem] = []
        for raw in array {
            guard let dict = raw as? [String: Any] else { continue }
            let name = Self.text(dict, ["vod_name", "name", "title"])
            let pic = Self.text(dict, ["vod_pic", "pic", "img"])
            let remark = Self.text(dict, ["vod_remarks", "remarks", "note"])
            let id = Self.text(dict, ["vod_id", "id", "url", "link"])
            guard !name.isEmpty || !id.isEmpty else { continue }
            items.append(VodItem(vodId: id.isEmpty ? name : id,
                                 vodName: name,
                                 vodPic: pic,
                                 vodRemarks: remark,
                                 siteKey: site.key))
        }
        return items
    }

    // MARK: - SiteProvider

    func home(completion: @escaping (Result<[VodItem], SiteError>) -> Void) {
        fetch(buildURL(["ac": "list"])) { result in
            switch result {
            case .success(let object):
                let items = self.vodItems(from: object)
                completion(items.isEmpty ? .failure(.empty) : .success(items))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func category(id: String, page: Int, extend: [String: String], completion: @escaping (Result<[VodItem], SiteError>) -> Void) {
        var query = ["ac": "list", "t": id, "pg": String(page)]
        for (key, value) in extend { query[key] = value }
        let url = site.url.isEmpty ? buildURL(query) : expand(site.url, classId: id, page: page, keyword: "")
        fetch(url) { result in
            switch result {
            case .success(let object):
                let items = self.vodItems(from: object)
                completion(items.isEmpty ? .failure(.empty) : .success(items))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func categories(completion: @escaping (Result<[SiteCategory], SiteError>) -> Void) {
        fetch(buildURL(["ac": "list"])) { result in
            switch result {
            case .success(let object):
                guard let dict = object as? [String: Any],
                      let classes = dict["class"] as? [Any] else {
                    completion(.success([]))
                    return
                }
                var categories: [SiteCategory] = []
                for raw in classes {
                    guard let item = raw as? [String: Any] else { continue }
                    let identifier = Self.text(item, ["type_id", "id", "typeId"])
                    let name = Self.text(item, ["type_name", "name", "title"])
                    if name.isEmpty && identifier.isEmpty { continue }
                    categories.append(SiteCategory(id: identifier.isEmpty ? name : identifier, name: name))
                }
                completion(.success(categories))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func detail(id: String, completion: @escaping (Result<VodDetail, SiteError>) -> Void) {
        fetch(detailURL(id: id)) { result in
            switch result {
            case .success(let object):
                guard var media = object as? [String: Any] else {
                    completion(.failure(.parse("详情返回格式无法识别")))
                    return
                }
                if let list = media["list"] as? [[String: Any]], let first = list.first {
                    media = first
                } else if let list = media["data"] as? [[String: Any]], let first = list.first {
                    media = first
                }
                let name = Self.text(media, ["vod_name", "name", "title"])
                let pic = Self.text(media, ["vod_pic", "pic", "img"])
                let content = Self.text(media, ["vod_content", "content", "desc"])
                let score = Self.text(media, ["vod_score", "score"])
                let remarks = Self.text(media, ["vod_remarks", "remarks"])
                let playFrom = Self.text(media, ["vod_play_from", "play_from"])
                let playUrl = Self.text(media, ["vod_play_url", "play_url"])
                var tabs = playFrom.isEmpty ? [] : playFrom.split(separator: "$").map { String($0) }
                let groups = JSSiteProvider.splitPlayGroups(playUrl)
                if tabs.isEmpty { tabs = (0..<max(groups.count, 1)).map { "线路\($0 + 1)" } }
                var quality: [String] = []
                if let raw = media["vod_quality"] as? String, !raw.isEmpty {
                    quality = raw.split(separator: "$").map { String($0) }
                }
                completion(.success(VodDetail(vodId: id,
                                             vodName: name.isEmpty ? id : name,
                                             vodPic: pic,
                                             vodContent: content,
                                             vodScore: score,
                                             vodYear: "",
                                             vodArea: "",
                                             vodType: "",
                                             vodRemarks: remarks,
                                             siteKey: self.site.key,
                                             tabs: tabs,
                                             lists: groups,
                                             quality: quality)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func search(keyword: String, page: Int, completion: @escaping (Result<[VodItem], SiteError>) -> Void) {
        fetch(searchURL(keyword: keyword, page: page)) { result in
            switch result {
            case .success(let object):
                let items = self.vodItems(from: object)
                completion(items.isEmpty ? .failure(.empty) : .success(items))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// API 源同样只做分类：直链放行，其余交给 `PlayResolver` 的嗅探/二次解析。
    func play(flag: String, url: String, completion: @escaping (Result<PlayResolution, SiteError>) -> Void) {
        if let direct = PlayURLClassifier.directMediaURL(url) {
            completion(.success(PlayResolution(url: direct, parseIndex: nil, needSniff: false)))
            return
        }
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(.parse("剧集地址为空")))
            return
        }
        completion(.success(PlayResolution(url: url, parseIndex: nil, needSniff: true)))
    }
}
