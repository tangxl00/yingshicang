import XCTest
@testable import Yingshicang

// MARK: - 测试替身

/// 可注入的 HTTP 出口：让播放解析链路完全离线、结果可证伪。
final class MockPlayTransport: PlayTransport {
    var responses: [String: HTTPResponse] = [:]
    var requestedURLs: [String] = []
    private let lock = NSLock()

    func stub(_ url: String, _ response: HTTPResponse) {
        lock.lock(); responses[url] = response; lock.unlock()
    }

    func get(_ url: String, completion: @escaping (HTTPResponse) -> Void) {
        lock.lock(); requestedURLs.append(url)
        let response = responses[url] ?? .failure(url, status: 404)
        lock.unlock()
        completion(response)
    }
}

/// 记录调用次数的 provider，用于断言「lazy 存在时不应再问 spider」。
final class RecordingProvider: SiteProvider {
    let site: SiteConfig
    private(set) var playCallCount = 0
    private(set) var lastFlag = ""
    var playResult: Result<PlayResolution, SiteError> = .success(.empty)
    private let lock = NSLock()

    init(site: SiteConfig) { self.site = site }

    func home(completion: @escaping (Result<[VodItem], SiteError>) -> Void) { completion(.failure(.empty)) }
    func category(id: String, page: Int, extend: [String: String],
                  completion: @escaping (Result<[VodItem], SiteError>) -> Void) { completion(.failure(.empty)) }
    func categories(completion: @escaping (Result<[SiteCategory], SiteError>) -> Void) { completion(.failure(.empty)) }
    func detail(id: String, completion: @escaping (Result<VodDetail, SiteError>) -> Void) { completion(.failure(.empty)) }
    func search(keyword: String, page: Int, completion: @escaping (Result<[VodItem], SiteError>) -> Void) { completion(.failure(.empty)) }

    func play(flag: String, url: String, completion: @escaping (Result<PlayResolution, SiteError>) -> Void) {
        lock.lock(); playCallCount += 1; lastFlag = flag; let result = playResult; lock.unlock()
        completion(result)
    }
}

/// 测试辅助：从一段配置 JSON 里取站点，避免手写 28 个字段的 memberwise init。
func testSite(_ json: String) -> SiteConfig {
    ConfigRepository.parse(text: json).sites[0]
}

/// 空对象参数。`[:]` 字面量在 `[Any]` 上下文里无法推断类型，必须显式构造。
func emptyObject() -> [String: Any] { [String: Any]() }

// MARK: - 解析三形态

/// 形态一（HTML 规则源）：直链快路径与「非直链需嗅探」的判定。
final class HTMLFormTests: XCTestCase {

    func testHTMLDirectLinkShorthandIsNormalized() {
        let site = testSite(#"{"sites":[{"key":"h1","name":"HTML源","type":0,"api":"https://h.example.com"}]}"#)
        let provider = HTMLSiteProvider(site: site)
        let expectation = expectation(description: "play")
        provider.play(flag: "线路1", url: "m3u8://cdn.example.com/a.m3u8") { result in
            if case .success(let resolution) = result {
                XCTAssertEqual(resolution.url, "http://cdn.example.com/a.m3u8")
                XCTAssertFalse(resolution.needSniff)
                XCTAssertNil(resolution.parseIndex)
            } else {
                XCTFail("直链应成功返回，实际 \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)
    }

    func testHTMLNonDirectPageNeedsSniff() {
        let site = testSite(#"{"sites":[{"key":"h1","name":"HTML源","type":0,"api":"https://h.example.com"}]}"#)
        let provider = HTMLSiteProvider(site: site)
        let expectation = expectation(description: "play")
        provider.play(flag: "线路1", url: "https://h.example.com/play/123-1-1.html") { result in
            if case .success(let resolution) = result {
                XCTAssertTrue(resolution.needSniff, "非直链应标记需要嗅探，而不是当作直链")
                XCTAssertNil(resolution.parseIndex)
            } else {
                XCTFail("分类阶段不应失败，实际 \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)
    }

    func testEmptyEpisodeURLFailsExplicitly() {
        let site = testSite(#"{"sites":[{"key":"h1","name":"HTML源","type":0,"api":"https://h.example.com"}]}"#)
        let provider = HTMLSiteProvider(site: site)
        let expectation = expectation(description: "play")
        provider.play(flag: "", url: "   ") { result in
            if case .failure(let error) = result {
                XCTAssertEqual(error, .parse("剧集地址为空"))
            } else {
                XCTFail("空地址必须显式失败，不能返回成功")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)
    }
}

/// 形态二（JSON API 源）：lazy 的 `json:` 前缀与 API 站点分类。
final class JSONFormTests: XCTestCase {

    func testAPIProviderNonDirectNeedsSniff() {
        let site = testSite(#"{"sites":[{"key":"a1","name":"API源","type":1,"api":"https://a.example.com/api.php/provide/vod"}]}"#)
        let provider = APISiteProvider(site: site)
        let expectation = expectation(description: "play")
        provider.play(flag: "线路1", url: "https://a.example.com/vodplay/9-1-1/") { result in
            if case .success(let resolution) = result {
                XCTAssertTrue(resolution.needSniff)
            } else {
                XCTFail("分类阶段不应失败，实际 \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)
    }

    func testLazyJSONPrefixExtractsURL() {
        let transport = MockPlayTransport()
        let site = testSite(#"{"sites":[{"key":"j1","name":"JSON源","type":1,"api":"https://j.example.com","lazy":"json:https://api.example.com/parse?url="}]}"#)
        transport.stub("https://api.example.com/parse?url=https://cdn.example.com/raw.m3u8",
                       HTTPResponse(ok: true, status: 200, content: #"{"url":"https://cdn.example.com/final.m3u8"}"#,
                                    headers: [:], url: "https://api.example.com/parse", data: nil))
        let resolver = PlayResolver(transport: transport, bundleProvider: { ConfigBundle() }, engines: JSEngineRegistry())
        let provider = RecordingProvider(site: site)
        let expectation = expectation(description: "resolve")
        resolver.resolve(site: site, provider: provider, flag: "线路1",
                         url: "https://cdn.example.com/raw.m3u8") { result in
            if case .success(let resolution) = result {
                XCTAssertEqual(resolution.url, "https://cdn.example.com/final.m3u8")
                XCTAssertFalse(resolution.needSniff)
            } else {
                XCTFail("lazy json: 应解析出最终地址，实际 \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(provider.playCallCount, 0, "lazy 存在时不应再问 provider")
        XCTAssertEqual(transport.requestedURLs.count, 1)
    }

    func testLazyJSONWithoutURLFieldFails() {
        let transport = MockPlayTransport()
        let site = testSite(#"{"sites":[{"key":"j2","name":"JSON源","type":1,"api":"https://j.example.com","lazy":"json:https://api.example.com/parse?url="}]}"#)
        transport.stub("https://api.example.com/parse?url=https://cdn.example.com/raw.m3u8",
                       HTTPResponse(ok: true, status: 200, content: #"{"code":0}"#, headers: [:],
                                    url: "https://api.example.com/parse", data: nil))
        let resolver = PlayResolver(transport: transport, bundleProvider: { ConfigBundle() }, engines: JSEngineRegistry())
        let provider = RecordingProvider(site: site)
        let expectation = expectation(description: "resolve")
        resolver.resolve(site: site, provider: provider, flag: "", url: "https://cdn.example.com/raw.m3u8") { result in
            if case .failure(let error) = result {
                XCTAssertNotNil(error.errorDescription)
            } else {
                XCTFail("「返回体无 url」必须失败，不能把入参当直链返回")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }
}

/// 形态三（JS 爬虫源）：spider 返回值映射与真 JS 执行。
final class JSFormTests: XCTestCase {

    func testSpiderParseJxMappingToParseIndex() {
        let jxPayload: [String: Any] = ["url": "https://cdn.example.com/raw.m3u8", "parse": 2, "jx": 1]
        let jx = JSSiteProvider.parsePlay(jxPayload)
        XCTAssertEqual(jx.url, "https://cdn.example.com/raw.m3u8")
        XCTAssertEqual(jx.parseIndex, 1, "parse=2 对应 parses 数组下标 1")
        XCTAssertFalse(jx.needSniff)

        let sniffPayload: [String: Any] = ["url": "https://cdn.example.com/raw.m3u8", "parse": 1, "jx": 0]
        let sniffOnly = JSSiteProvider.parsePlay(sniffPayload)
        XCTAssertNil(sniffOnly.parseIndex)
        XCTAssertTrue(sniffOnly.needSniff)

        let directPayload: [String: Any] = ["url": "https://cdn.example.com/a.m3u8", "parse": 0]
        let direct = JSSiteProvider.parsePlay(directPayload)
        XCTAssertNil(direct.parseIndex)
        XCTAssertFalse(direct.needSniff)
    }

    func testSpiderNumberTypesAreTolerant() {
        // JS 桥可能把数字以字符串/NSNumber 形态回传，两种都要能解析出 parseIndex。
        let stringPayload: [String: Any] = ["url": "https://cdn.example.com/a.mp4", "parse": "3", "jx": "1"]
        let fromString = JSSiteProvider.parsePlay(stringPayload)
        XCTAssertEqual(fromString.parseIndex, 2)
        let numberPayload: [String: Any] = ["url": "https://cdn.example.com/a.mp4",
                                            "parse": NSNumber(value: 1), "jx": NSNumber(value: 1)]
        let fromNumber = JSSiteProvider.parsePlay(numberPayload)
        XCTAssertEqual(fromNumber.parseIndex, 0)
    }

    func testJSSpiderActuallyExecutesAndReturnsResult() {
        let engine = JSEngine(scope: "test-js-form", requestPolicy: JSRequestPolicy(), promiseTimeout: 1)
        let script = """
        globalThis.__JS_SPIDER__ = {
          play: function(setting, params){
            return {url: params.url + "?token=abc", parse: 0};
          }
        };
        """
        XCTAssertNil(engine.evaluate(script), "脚本应无异常")
        let result = engine.callSpider("play", arguments: [["key": "k"], ["url": "https://cdn.example.com/a.m3u8"]])
        switch result {
        case .success(let value):
            let resolution = JSSiteProvider.parsePlay(value)
            XCTAssertEqual(resolution.url, "https://cdn.example.com/a.m3u8?token=abc")
            XCTAssertFalse(resolution.needSniff)
        case .failure(let error):
            XCTFail("spider 调用应成功，实际 \(error)")
        }
    }

    func testMissingSpiderMethodFailsExplicitly() {
        let engine = JSEngine(scope: "test-js-missing", requestPolicy: JSRequestPolicy(), promiseTimeout: 1)
        XCTAssertNil(engine.evaluate("globalThis.__JS_SPIDER__ = {};"))
        switch engine.callSpider("play", arguments: [emptyObject(), emptyObject()]) {
        case .success:
            XCTFail("方法缺失必须失败，不能返回空值当成功")
        case .failure(let error):
            XCTAssertEqual(error, .methodMissing("play"))
        }
    }
}

// MARK: - async Promise（P1-2）

final class PromiseResolutionTests: XCTestCase {

    private func engine(_ scope: String) -> JSEngine {
        JSEngine(scope: scope, requestPolicy: JSRequestPolicy(), promiseTimeout: 1)
    }

    func testThenResolveIsConsumed() {
        let engine = self.engine("promise-success")
        let script = """
        globalThis.__JS_SPIDER__ = {
          search: function(setting, params){
            var payload = {list:[{vod_name: params.wd, vod_id: "9"}]};
            return { then: function(resolve, reject){ resolve(payload); } };
          }
        };
        """
        XCTAssertNil(engine.evaluate(script))
        switch engine.callSpider("search", arguments: [["key": "k"], ["wd": "三体"]]) {
        case .success(let value):
            guard let dict = value as? [String: Any],
                  let list = dict["list"] as? [[String: Any]] else {
                XCTFail("Promise resolve 的载荷应被展开成字典，实际 \(String(describing: value))")
                return
            }
            XCTAssertEqual(list.first?["vod_name"] as? String, "三体")
        case .failure(let error):
            XCTFail("Promise 正常 resolve 不应失败，实际 \(error)")
        }
    }

    func testPromiseTimeoutFails() {
        let engine = self.engine("promise-timeout")
        let script = """
        globalThis.__JS_SPIDER__ = {
          search: function(){ return { then: function(resolve, reject){ /* 永不 resolve */ } }; }
        };
        """
        XCTAssertNil(engine.evaluate(script))
        switch engine.callSpider("search", arguments: [emptyObject(), emptyObject()]) {
        case .success:
            XCTFail("永不 resolve 的 Promise 必须超时失败，不能当成同步返回值")
        case .failure(let error):
            if case .promiseTimeout = error { /* 期望 */ } else {
                XCTFail("应报 promiseTimeout，实际 \(error)")
            }
        }
    }

    func testPromiseRejectionPropagates() {
        let engine = self.engine("promise-reject")
        let script = """
        globalThis.__JS_SPIDER__ = {
          detail: function(){ return { then: function(resolve, reject){ reject("接口返回 403"); } }; }
        };
        """
        XCTAssertNil(engine.evaluate(script))
        switch engine.callSpider("detail", arguments: [emptyObject(), emptyObject()]) {
        case .success:
            XCTFail("被 reject 的 Promise 必须失败")
        case .failure(let error):
            guard case .promiseRejected(let reason) = error else {
                XCTFail("应报 promiseRejected，实际 \(error)")
                return
            }
            XCTAssertTrue(reason.contains("403"))
        }
    }
}

// MARK: - 双站并发隔离（P1-3）

final class ConcurrentSiteIsolationTests: XCTestCase {

    func testTwoSitesDoNotShareSpiderState() {
        let registry = JSEngineRegistry()
        let siteA = testSite(#"{"sites":[{"key":"alpha","name":"A","type":3,"api":"./a.js","host":"https://a.example.com"}]}"#)
        let siteB = testSite(#"{"sites":[{"key":"beta","name":"B","type":3,"api":"./b.js","host":"https://b.example.com"}]}"#)
        let providerA = JSSiteProvider(site: siteA, engines: registry)
        let providerB = JSSiteProvider(site: siteB, engines: registry)

        // 直接给两个站点各自的引擎装不同的 spider 实现（跳过网络装载）。
        let engineA = registry.engine(for: siteA)
        let engineB = registry.engine(for: siteB)
        XCTAssertNotEqual(engineA.scope, engineB.scope, "不同站点必须持有不同引擎作用域")
        XCTAssertNil(engineA.evaluate("globalThis.__JS_SPIDER__ = { search: function(s, p){ return {list:[{vod_name:\"A:\" + p.wd, vod_id:\"1\"}]}; } };"))
        XCTAssertNil(engineB.evaluate("globalThis.__JS_SPIDER__ = { search: function(s, p){ return {list:[{vod_name:\"B:\" + p.wd, vod_id:\"2\"}]}; } };"))

        // 8 路并发（4 次 A + 4 次 B），断言各自结果不串味。
        let expectation = expectation(description: "concurrent")
        expectation.expectedFulfillmentCount = 8
        let lock = NSLock()
        var observed: [String: [String]] = [:]

        for index in 0..<4 {
            providerA.search(keyword: "kwA\(index)", page: 1) { result in
                lock.lock()
                if case .success(let items) = result { observed["A", default: []].append(items.first?.vodName ?? "<nil>") }
                lock.unlock()
                expectation.fulfill()
            }
            providerB.search(keyword: "kwB\(index)", page: 1) { result in
                lock.lock()
                if case .success(let items) = result { observed["B", default: []].append(items.first?.vodName ?? "<nil>") }
                lock.unlock()
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 20)

        let aResults = observed["A"] ?? []
        let bResults = observed["B"] ?? []
        XCTAssertEqual(aResults.count, 4, "A 站 4 次请求都应有结果，实际 \(aResults)")
        XCTAssertEqual(bResults.count, 4, "B 站 4 次请求都应有结果，实际 \(bResults)")
        for value in aResults {
            XCTAssertTrue(value.hasPrefix("A:"), "A 站结果被污染：\(value)")
        }
        for value in bResults {
            XCTAssertTrue(value.hasPrefix("B:"), "B 站结果被污染：\(value)")
        }
    }

    func testRegistryReusesOneEnginePerSiteAndSeparatesLazyScope() {
        let registry = JSEngineRegistry()
        let site = testSite(#"{"sites":[{"key":"gamma","name":"G","type":3,"api":"./g.js","host":"https://g.example.com"}]}"#)
        let first = registry.engine(for: site)
        let second = registry.engine(for: site)
        XCTAssertTrue(first === second, "同一站点必须复用同一引擎，避免重复求值运行库")
        let lazy = registry.lazyEngine(for: site)
        XCTAssertFalse(first === lazy, "lazy 脚本必须使用独立作用域，不能污染 spider 运行库")
        XCTAssertEqual(registry.scopes().count, 2)
    }
}

// MARK: - lazy 前缀（P1-6）

final class LazyPrefixTests: XCTestCase {

    /// 修复前 type=3 站点走 `JSSiteProvider.play`，lazy 逻辑对 JS 站点是死代码。
    func testJSSiteLazyIsExecutedBeforeSpiderPlay() {
        let site = testSite("""
        {"sites":[{"key":"js-lazy","name":"JS懒","type":3,"api":"./js-lazy.js",
                   "host":"https://js.example.com",
                   "lazy":"js:input = input.replace('/play/', '/m3u8/') + '.m3u8';"}]}
        """)
        let provider = RecordingProvider(site: site)
        let resolver = PlayResolver(transport: MockPlayTransport(), bundleProvider: { ConfigBundle() },
                                    engines: JSEngineRegistry())
        let expectation = expectation(description: "lazy")
        resolver.resolve(site: site, provider: provider, flag: "线路1",
                         url: "https://js.example.com/play/abc.html") { result in
            if case .success(let resolution) = result {
                XCTAssertEqual(resolution.url, "https://js.example.com/m3u8/abc.html.m3u8",
                               "lazy 脚本必须对 JS 站点生效")
                XCTAssertFalse(resolution.needSniff)
            } else {
                XCTFail("lazy 应执行成功，实际 \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 15)
        XCTAssertEqual(provider.playCallCount, 0, "lazy 已给出结果时不应再调 spider.play（P1-6 死代码修复点）")
    }

    func testLazyScriptThrowingFailsInsteadOfReturningInputAsDirectLink() {
        let site = testSite("""
        {"sites":[{"key":"js-bad","name":"JS坏","type":3,"api":"./js-bad.js",
                   "host":"https://js.example.com","lazy":"js:throw new Error('规则脚本损坏');"}]}
        """)
        let provider = RecordingProvider(site: site)
        let resolver = PlayResolver(transport: MockPlayTransport(), bundleProvider: { ConfigBundle() },
                                    engines: JSEngineRegistry())
        let expectation = expectation(description: "lazy fail")
        resolver.resolve(site: site, provider: provider, flag: "", url: "https://js.example.com/play/x.html") { result in
            if case .failure(let error) = result {
                // P1-4：失败必须走 failure，不能把入参当直链返回 .success。
                XCTAssertTrue(error.errorDescription?.contains("lazy") ?? false,
                              "错误信息应指明 lazy 脚本失败，实际 \(error.errorDescription ?? "nil")")
            } else {
                XCTFail("lazy 脚本抛异常时必须返回失败，不能伪装成功")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 15)
    }

    func testLazyReturningEmptyStringFails() {
        let site = testSite("""
        {"sites":[{"key":"js-empty","name":"JS空","type":0,"api":"https://e.example.com","lazy":"js:input = '';"}]}
        """)
        let provider = RecordingProvider(site: site)
        let resolver = PlayResolver(transport: MockPlayTransport(), bundleProvider: { ConfigBundle() },
                                    engines: JSEngineRegistry())
        let expectation = expectation(description: "empty")
        resolver.resolve(site: site, provider: provider, flag: "", url: "https://e.example.com/play/1.html") { result in
            if case .failure = result { /* 期望 */ } else {
                XCTFail("lazy 返回空地址必须失败，不能当成功")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 15)
    }
}

// MARK: - 二次解析与嗅探（P1-1 / P1-4）

final class SecondaryParseTests: XCTestCase {

    func testParseIndexIsConsumedFromParsesArray() {
        let transport = MockPlayTransport()
        transport.stub("https://parse.example.com/jx?url=https://cdn.example.com/raw.m3u8",
                       HTTPResponse(ok: true, status: 200,
                                    content: #"{"data":{"url":"https://cdn.example.com/parsed.m3u8"}}"#,
                                    headers: [:], url: "https://parse.example.com/jx", data: nil))
        let bundle = ConfigRepository.parse(text: """
        {"parses":[{"name":"解析1","url":"https://parse.example.com/jx?url=","type":1}]}
        """)
        let site = testSite(#"{"sites":[{"key":"s1","name":"源","type":0,"api":"https://s.example.com"}]}"#)
        let resolver = PlayResolver(transport: transport, bundleProvider: { bundle }, engines: JSEngineRegistry())
        let provider = RecordingProvider(site: site)
        provider.playResult = .success(PlayResolution(url: "https://cdn.example.com/raw.m3u8",
                                                      parseIndex: 0, needSniff: false))
        let expectation = expectation(description: "secondary")
        resolver.resolve(site: site, provider: provider, flag: "线路1",
                         url: "https://cdn.example.com/raw.m3u8") { result in
            if case .success(let resolution) = result {
                XCTAssertEqual(resolution.url, "https://cdn.example.com/parsed.m3u8",
                               "parseIndex 必须真正触发二次解析（P1-1）")
                XCTAssertNil(resolution.parseIndex)
            } else {
                XCTFail("二次解析应成功，实际 \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(provider.playCallCount, 1, "直链快路径未命中时才应问 provider")
    }

    func testParseIndexOutOfRangeFails() {
        let bundle = ConfigRepository.parse(text: #"{"parses":[]}"#)
        let resolver = PlayResolver(transport: MockPlayTransport(), bundleProvider: { bundle },
                                    engines: JSEngineRegistry())
        let expectation = expectation(description: "oob")
        resolver.applySecondaryParse(url: "https://cdn.example.com/raw.m3u8", parseIndex: 3) { result in
            if case .failure(let error) = result {
                XCTAssertTrue(error.errorDescription?.contains("越界") ?? false)
            } else {
                XCTFail("下标越界必须失败")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)
    }

    func testSniffExtractsMediaURLFromPage() {
        let transport = MockPlayTransport()
        transport.stub("https://page.example.com/play/1.html",
                       HTTPResponse(ok: true, status: 200,
                                    content: #"<script>var url="https:\/\/cdn.example.com\/hls\/index.m3u8";</script>"#,
                                    headers: [:], url: "https://page.example.com/play/1.html", data: nil))
        let site = testSite(#"{"sites":[{"key":"sn","name":"嗅探","type":0,"api":"https://page.example.com"}]}"#)
        let resolver = PlayResolver(transport: transport, bundleProvider: { ConfigBundle() },
                                    engines: JSEngineRegistry())
        let provider = RecordingProvider(site: site)
        provider.playResult = .success(PlayResolution(url: "https://page.example.com/play/1.html",
                                                     parseIndex: nil, needSniff: true))
        let expectation = expectation(description: "sniff")
        resolver.resolve(site: site, provider: provider, flag: "", url: "https://page.example.com/play/1.html") { result in
            if case .success(let resolution) = result {
                XCTAssertEqual(resolution.url, "https://cdn.example.com/hls/index.m3u8")
                XCTAssertFalse(resolution.needSniff)
            } else {
                XCTFail("嗅探应命中 m3u8，实际 \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    func testSniffWithoutMediaFails() {
        let transport = MockPlayTransport()
        transport.stub("https://page.example.com/play/1.html",
                       HTTPResponse(ok: true, status: 200, content: "<html>暂无资源</html>",
                                    headers: [:], url: "https://page.example.com/play/1.html", data: nil))
        let resolver = PlayResolver(transport: transport, bundleProvider: { ConfigBundle() },
                                    engines: JSEngineRegistry())
        let expectation = expectation(description: "sniff fail")
        resolver.sniff(url: "https://page.example.com/play/1.html") { result in
            if case .failure(let error) = result {
                XCTAssertTrue(error.errorDescription?.contains("未在响应中找到") ?? false,
                              "嗅探失败必须给出可定位原因，实际 \(error.errorDescription ?? "nil")")
            } else {
                XCTFail("页面里没有媒体地址时必须失败，不能返回入参当直链")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }
}

// MARK: - req 越权（P1-5）

final class RequestPolicyTests: XCTestCase {

    func testRejectsDangerousSchemes() {
        let policy = JSRequestPolicy()
        for url in ["file:///etc/passwd", "data:text/html,<script>1</script>",
                    "ftp://example.com/a.mp4", "javascript:alert(1)"] {
            XCTAssertFalse(policy.allows(url), "\(url) 必须被拒绝")
        }
    }

    func testRejectsPrivateAndLoopbackByDefault() {
        let policy = JSRequestPolicy()
        for url in ["http://127.0.0.1/admin", "http://localhost:8080/api",
                    "http://192.168.1.1/", "http://10.0.0.5/x", "http://172.16.3.4/",
                    "http://169.254.169.254/latest/meta-data/"] {
            XCTAssertFalse(policy.allows(url), "\(url) 属内网/回环，默认必须拒绝")
        }
        XCTAssertTrue(policy.allows("https://cdn.example.com/a.m3u8"), "公网地址默认放行")
    }

    func testWhitelistRestrictsToSameSite() {
        let policy = JSRequestPolicy(allowedHosts: ["example.com"])
        XCTAssertTrue(policy.allows("https://api.example.com/vod"), "子域属同站，放行")
        XCTAssertTrue(policy.allows("https://example.com/vod"))
        XCTAssertFalse(policy.allows("https://evil.example.net/vod"), "无关第三方域必须拒绝")
        XCTAssertFalse(policy.allows("https://cdn.other.com/a.m3u8"))
    }

    func testWhitelistCanPermitLanHostWhenExplicit() {
        let policy = JSRequestPolicy(allowedHosts: ["192.168.1.10"])
        XCTAssertTrue(policy.allows("http://192.168.1.10:8080/webdav/"), "显式白名单允许局域网自建服务")
    }

    func testBridgeReqBlocksIntranetBeforeNetwork() {
        let engine = JSEngine(scope: "policy-bridge", requestPolicy: JSRequestPolicy(), promiseTimeout: 1)
        let script = """
        globalThis.__JS_SPIDER__ = {
          probe: function(){
            var r = req("http://192.168.1.1/admin/config");
            return { blocked: r.blocked, status: r.status, ok: r.ok };
          }
        };
        """
        XCTAssertNil(engine.evaluate(script))
        switch engine.callSpider("probe", arguments: []) {
        case .success(let value):
            guard let dict = value as? [String: Any] else {
                XCTFail("应返回字典，实际 \(String(describing: value))")
                return
            }
            XCTAssertEqual(dict["blocked"] as? Bool, true, "内网请求必须在桥层被拦截")
            XCTAssertEqual((dict["status"] as? NSNumber)?.intValue, 403)
            XCTAssertEqual(dict["ok"] as? Bool, false)
        case .failure(let error):
            XCTFail("探针调用本身应成功，实际 \(error)")
        }
    }
}

// MARK: - 凭证存储（P2）

final class CredentialStorageTests: XCTestCase {

    /// 安全回归的核心断言：密码既不写入 UserDefaults，也不从 UserDefaults 读取。
    ///
    /// 特意不依赖 Keychain 是否可用（CI 上 `CODE_SIGNING_ALLOWED=NO` 可能导致
    /// `errSecMissingEntitlement`），否则这条用例会变成环境探针而不是安全断言：
    /// 无论 Keychain 写成功与否，「明文不出现在 UserDefaults」「getter 不读 UserDefaults」
    /// 这两个性质都必须成立。
    func testWebDavPasswordNeverTouchesUserDefaults() {
        let legacyKey = "tpc_settings.webDavPassword"
        defer {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            Settings.shared.webDavPassword = ""
        }

        // ① 写入路径：设置一次密码后，任何 UserDefaults 值都不应含有该明文。
        Settings.shared.webDavPassword = "s3cret-token"
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            if let text = value as? String {
                XCTAssertFalse(text.contains("s3cret-token"),
                               "密钥明文出现在 UserDefaults 键 \(key)，凭证必须存 Keychain")
            }
            XCTAssertFalse(key.hasSuffix("webDavPassword"),
                           "UserDefaults 不应存在 webDavPassword 键（实际键：\(key)）")
        }

        // ② 读取路径：往旧的 UserDefaults 键写诱饵，getter 必须读不到它。
        //    修复前 getter 直接 string("webDavPassword")，这条断言必失败。
        UserDefaults.standard.set("plaintext-decoy", forKey: legacyKey)
        XCTAssertNotEqual(Settings.shared.webDavPassword, "plaintext-decoy",
                          "getter 仍在读 UserDefaults 明文（Keychain 迁移未生效）")
    }

    /// Keychain 往返。无签名 entitlement 的环境（如 CI 模拟器）会拒绝 Keychain，
    /// 此时明确 skip 并说明原因，不伪造通过。
    func testKeychainRoundTripWhenAvailable() throws {
        let account = "ci-roundtrip-probe"
        defer { KeychainStore.remove(account: account) }

        guard KeychainStore.set("probe-value", account: account) else {
            throw XCTSkip("当前环境无 Keychain entitlement（CI 未签名构建），跳过往返验证")
        }
        XCTAssertEqual(KeychainStore.get(account: account), "probe-value")
        KeychainStore.remove(account: account)
        XCTAssertEqual(KeychainStore.get(account: account), "", "删除后应读不到")
    }
}
