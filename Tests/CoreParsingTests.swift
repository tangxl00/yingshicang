import XCTest
@testable import Yingshicang

/// HTML 规则拆分（`A;B;C` 分段 / `&&` 下钻 / `||` 并列候选）。
final class HTMLRuleTests: XCTestCase {

    func testSplitFieldsBySemicolon() {
        XCTAssertEqual(HTMLRule.splitFields("body&&.item&&Text;.list&&a&&href;.note"), ["body&&.item&&Text", ".list&&a&&href", ".note"])
    }

    func testSplitFieldsIgnoresSemicolonInBracketsAndQuotes() {
        XCTAssertEqual(HTMLRule.splitFields("a[href$='.html']:eq(1)&&Text"), ["a[href$='.html']:eq(1)&&Text"])
    }

    func testFieldAt() {
        XCTAssertEqual(HTMLRule.field("a;b;c", at: 1), "b")
        XCTAssertEqual(HTMLRule.field("a", at: 5), "a", "越界回退首段")
    }

    func testSplitChain() {
        XCTAssertEqual(HTMLRule.splitChain("body&&.item&&Text"), ["body", ".item", "Text"])
    }

    func testSplitAlternatives() {
        XCTAssertEqual(HTMLRule.splitAlternatives(".pic||.thumb||img"), [".pic", ".thumb", "img"])
    }

    func testTokenClassification() {
        XCTAssertTrue(HTMLRule.isTextToken("Text"))
        XCTAssertTrue(HTMLRule.isHtmlToken("Html"))
        XCTAssertTrue(HTMLRule.looksLikeAttribute("href"))
        XCTAssertFalse(HTMLRule.looksLikeAttribute(".class"))
        XCTAssertFalse(HTMLRule.looksLikeAttribute("#id"))
    }
}

/// 选择器执行（SwiftSoup 宿主实现，与 U01Gate 的 cheerio 版语义对齐）。
final class HTMLSelectorTests: XCTestCase {

    private let html = """
    <html><body>
    <ul class="list">
      <li><a class="pic" href="/tv/1/" title="国产剧"><img src="/upload/tv1.jpg" data-echo="https://cdn.example.com/tv1.jpg"/></a><span class="note">更新至12集</span></li>
      <li><a class="pic" href="/tv/2/" title="欧美剧"><img src="/upload/tv2.jpg"/></a><span class="note">全24集</span></li>
      <li><a class="pic" href="/tv/3/" title="日韩剧"><img src="/upload/tv3.jpg"/></a><span class="note">HD</span></li>
    </ul>
    <div class="detail"><h1>三体</h1><span data-id="abc123">类型</span></div>
    </body></html>
    """

    func testPdfhChainWithEq() {
        XCTAssertEqual(HTMLSelector.shared.pdfh(html, "body&&ul.list&&li:eq(2)&&a&&title"), "日韩剧")
    }

    func testPdfhTextExtraction() {
        XCTAssertEqual(HTMLSelector.shared.pdfh(html, "body&&div.detail&&h1&&Text"), "三体")
    }

    func testPdfhAttributeSelectorAndAttrName() {
        XCTAssertEqual(HTMLSelector.shared.pdfh(html, "body&&[data-id=abc123]&&data-id"), "abc123")
    }

    func testPdfhAlternatives() {
        // .missing 未命中 → 回退 a.pic
        XCTAssertEqual(HTMLSelector.shared.pdfh(html, "body&&li:eq(1)&&.missing||a.pic&&href"), "/tv/2/")
    }

    func testPdList() {
        let hrefs = HTMLSelector.shared.pd(html, "body&&ul.list&&li&&a&&href")
        XCTAssertEqual(hrefs, ["/tv/1/", "/tv/2/", "/tv/3/"])
    }

    func testSrcAttributeAlias() {
        // src 别名应覆盖 data-echo（属性别名链里 src 在前）
        let value = HTMLSelector.shared.pdfh(html, "body&&li:eq(0)&&img&&src")
        XCTAssertFalse(value.isEmpty, "src 或其别名（data-src/data-original/data-echo）至少命中一个")
    }
}

/// 配置解析（JSON / 容错 JSON / 多仓）。
final class ConfigParserTests: XCTestCase {

    func testParsePlainJSON() {
        let text = """
        {"sites":[{"key":"aa","name":"站点A","type":0,"api":"https://a.example.com","searchable":1},
                  {"key":"bb","name":"站点B","type":1,"api":"https://b.example.com/api.php/provide/vod"}],
         "lives":[{"name":"直播1","url":"https://live.example.com/txt"}],
         "parses":[{"name":"解析1","url":"https://p.example.com/?url=","type":0}]}
        """
        let bundle = ConfigRepository.parse(text: text)
        XCTAssertEqual(bundle.sites.count, 2)
        XCTAssertEqual(bundle.sites[0].key, "aa")
        XCTAssertEqual(bundle.sites[1].type, 1)
        XCTAssertEqual(bundle.lives.count, 1)
        XCTAssertEqual(bundle.parses.count, 1)
    }

    func testParseTolerantJSONWithCommentsAndTrailingComma() {
        let text = """
        // 配置注释
        {
          "sites": [ {"key":"x","name":"X","type":3,"api":"./x.js",}, /* 行内注释 */
          ],
        }
        """
        let bundle = ConfigRepository.parse(text: text)
        XCTAssertEqual(bundle.sites.count, 1)
        XCTAssertEqual(bundle.sites[0].type, 3)
    }

    func testJarSiteFlagged() {
        let text = """
        {"sites":[{"key":"spider1","name":"蜘蛛源","type":3,"api":"csp_Test","jar":"https://jar.example.com/x.jar"}]}
        """
        let bundle = ConfigRepository.parse(text: text)
        XCTAssertTrue(bundle.sites[0].isJarSpider, "带 jar 字段的站点必须被识别为 jar 源")
        let provider = SiteProviderFactory.make(site: bundle.sites[0])
        XCTAssertTrue(provider is UnsupportedSiteProvider, "jar 源必须路由到显式不支持的 Provider")
    }

    func testStoreIndexParsing() {
        let text = """
        {"urls":["https://a.example.com/1.json","https://b.example.com/2.txt"]}
        """
        let stores = ConfigParser.parseStoreIndex(text: text)
        XCTAssertEqual(stores.count, 1)
        XCTAssertEqual(stores[0].lines.count, 2)
        XCTAssertEqual(stores[0].lines[1].url, "https://b.example.com/2.txt")
    }

    func testFieldAliases() {
        // search_url 下划线别名与 searchUrl 等价
        let text = """
        {"sites":[{"key":"a","name":"A","type":0,"api":"https://a.com","search_url":"/search?wd={wd}"}]}
        """
        let bundle = ConfigRepository.parse(text: text)
        XCTAssertEqual(bundle.sites[0].searchUrl, "/search?wd={wd}")
    }
}

/// 直播源文本解析（`频道名$地址`）。
final class LiveParserTests: XCTestCase {

    func testParseChannels() {
        let text = """
        #EXTM3U 头部忽略
        央视一台,https://cctv1.example.com/live.m3u8
        央视二台$https://cctv2.example.com/live.m3u8$备用线路
        //注释行
        卫视一台$https://ws1.example.com/index.m3u8
        坏行没有分隔符
        """
        let channels = LiveParser.parse(text: text, sourceName: "测试源")
        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].name, "央视二台")
        XCTAssertEqual(channels[0].url, "https://cctv2.example.com/live.m3u8", "多线路取第一条")
        XCTAssertEqual(channels[1].name, "卫视一台")
        XCTAssertEqual(channels[1].sourceName, "测试源")
    }
}

/// BodyDecoder 编码兜底。
final class BodyDecoderTests: XCTestCase {

    /// iOS SDK 的 String.Encoding 没有 .gb18030 成员，
    /// 与产品层（HTTPClient.BodyDecoder）同源：经 CFString 编码表换算。
    private static let gb18030: String.Encoding = {
        let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }()

    func testUTF8() {
        let data = "国产剧".data(using: .utf8)!
        XCTAssertEqual(BodyDecoder.decode(data, contentType: "text/html; charset=utf-8"), "国产剧")
    }

    func testGB18030() {
        let data = "国产剧".data(using: Self.gb18030)!
        let out = BodyDecoder.decode(data, contentType: "text/html")
        XCTAssertTrue(out.contains("国产剧"), "GBK 页面应按 meta/兜底解码，实际: \(out)")
    }

    func testContentTypeCharsetWins() {
        let data = "电视剧".data(using: Self.gb18030)!
        let out = BodyDecoder.decode(data, contentType: "text/html; charset=gbk")
        XCTAssertEqual(out, "电视剧")
    }
}
