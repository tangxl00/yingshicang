import XCTest
import JavaScriptCore
@testable import U01Gate

/// U-01 门禁用例（架构文档第 9 章）：cheerio.min.js 能否在 JavaScriptCore 中运行。
/// 五条可证伪断言：
/// - C-1 加载不抛异常（globalThis.cheerio 暴露成功）
/// - C-2 可构造 DOM（cheerio.load）
/// - C-3 选择器命中（class / :eq(n) / 属性选择器）
/// - C-4 $.html(node) 返回字符串（drpy 的 pdfh 契约依赖）
/// - C-5 真实 pdfh 调用（含 :eq、属性选择器、baseUrl 拼接）
///
/// 判定（结果记录于仓库根 KNOWN_DIFFERENCES.md）：
/// - A：五条全部通过 → 维持「JS 引擎 + cheerio」原设计
/// - C：base 全挂但 shimmed 组全过 → 注入最小 Node 全局垫片（仅类型与编码）
/// - B：shimmed 仍挂 → 解析层降级为宿主 Swift 实现（本工程已有 SwiftSoup 版兜底）
final class U01CheerioProbeTests: XCTestCase {

    private func fixtureHTML() -> String {
        // 测试 target 自身的资源包（.copy("Fixtures")）
        let bundle = Bundle.module
        let candidates = [
            bundle.resourceURL?.appendingPathComponent("Fixtures/sample.html"),
            bundle.resourceURL?.appendingPathComponent("sample.html")
        ]
        let url = candidates.compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path) }
            ?? bundle.resourceURL.flatMap { root in
                FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                    .compactMap { $0 as? URL }
                    .first { $0.lastPathComponent == "sample.html" }
            }
        guard let url = url else {
            XCTFail("sample.html fixture 缺失")
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 注入 pdfh 驱动（C-5 用，依赖 cheerio 已装载成功）。
    private func installDriver(_ context: JSContext) -> Bool {
        U01Probe.installPdfhDriver(context)
    }

    // MARK: - 基础组（无垫片）

    func testC1_LoadWithoutException() {
        let (_, result) = U01Probe.load(shimmed: false)
        guard case .ok = result else {
            XCTFail("C-1 失败（无垫片装载）: \(result) —— 若 shimmed 组通过则为判定 C")
            return
        }
    }

    func testC2_ConstructDOM() throws {
        let (context, load) = U01Probe.load(shimmed: false)
        guard case .ok = load else { throw XCTSkip("C-1 未通过，C-2 无意义（见 shimmed 组）") }
        let out = context.evaluateScript("""
        (function(){
            var $ = cheerio.load('<div class="wrap"><p class="title">Hi</p></div>');
            return { ok: typeof $ === 'function', text: $('.title').text() };
        })()
        """)
        let text = out?.objectForKeyedSubscript("text")?.toString()
        XCTAssertTrue(out?.objectForKeyedSubscript("ok")?.toBool() == true, "cheerio.load 未返回工厂函数")
        XCTAssertEqual(text, "Hi", "DOM 构造或查询失败")
    }

    func testC3_SelectorHit() throws {
        let (context, load) = U01Probe.load(shimmed: false)
        guard case .ok = load else { throw XCTSkip("C-1 未通过（见 shimmed 组）") }
        let html = fixtureHTML()
        context.setObject(html, forKeyedSubscript: "html" as NSString)
        let out = context.evaluateScript("""
        (function(){
            var $ = cheerio.load(html);
            var firstTitle = $('ul.stui-vodlist li.item:eq(0) a.pic').attr('title');
            var secondHref = $('ul.stui-vodlist li:eq(1) .pic').attr('href');
            var attrSel = $('[data-id=abc123]').text();
            var count = $('li.item').length;
            return [firstTitle, secondHref, attrSel, count].join('||');
        })()
        """)?.toString() ?? ""
        let parts = out.components(separatedBy: "||")
        XCTAssertEqual(parts.count, 4, "返回结构异常: \(out)")
        XCTAssertEqual(parts[0], "国产剧", "基础选择器 + :eq(0) 未命中")
        XCTAssertEqual(parts[1], "/tv/2/", ":eq(1) 下钻未命中")
        XCTAssertEqual(parts[2], "类型", "属性选择器 [data-id=abc123] 未命中")
        XCTAssertEqual(parts[3], "3", "列表计数不符")
    }

    func testC4_HtmlReturnsString() throws {
        let (context, load) = U01Probe.load(shimmed: false)
        guard case .ok = load else { throw XCTSkip("C-1 未通过（见 shimmed 组）") }
        context.setObject(fixtureHTML(), forKeyedSubscript: "html" as NSString)
        let out = context.evaluateScript("""
        (function(){
            var $ = cheerio.load(html);
            var node = $('div.detail');
            var htmlOut = $.html(node);
            var outer = node.html();
            return [typeof htmlOut, typeof outer].join('||');
        })()
        """)?.toString() ?? ""
        let parts = out.components(separatedBy: "||")
        XCTAssertEqual(parts.count, 2, "返回结构异常: \(out)")
        XCTAssertEqual(parts[0], "string", "$.html(node) 必须返回 string（drpy 的 pdfh 契约），实际 \(parts[0])")
        XCTAssertEqual(parts[1], "string", "node.html() 必须返回 string，实际 \(parts[1])")
    }

    func testC5_RealPdfhCall() throws {
        let (context, load) = U01Probe.load(shimmed: false)
        guard case .ok = load else { throw XCTSkip("C-1 未通过（见 shimmed 组）") }
        guard installDriver(context) else {
            XCTFail("pdfh.driver.js 注入失败（资源缺失）")
            return
        }
        context.setObject(fixtureHTML(), forKeyedSubscript: "html" as NSString)
        let out = context.evaluateScript("""
        (function(){
            var r1 = pdfh(html, 'body&&ul.stui-vodlist&&li.item:eq(2)&&a&&title');   // 链式下钻 + :eq
            var r2 = pdfh(html, 'body&&div.detail&&h1&&Text');                       // Text 提取
            var r3 = pdfh(html, 'body&&[data-id=abc123]&&data-id');                  // 属性选择器 + 属性名提取
            var r4 = pd(html, 'body&&ul.stui-vodlist&&li:eq(1)&&a.pic&&href', 'https://v.example.com');  // baseUrl 拼接
            var r5 = pd(html, 'body&&ul.stui-vodlist&&li:eq(0)&&img&&data-echo', 'https://v.example.com'); // 绝对地址直通
            return [r1, r2, r3, r4, r5].join('\\u0001');
        })()
        """)?.toString() ?? ""
        let parts = out.components(separatedBy: "\u{0001}")
        XCTAssertEqual(parts.count, 5, "返回结构异常: \(out)")
        XCTAssertEqual(parts[0], "日韩剧", "链式下钻 + :eq(2) 未命中")
        XCTAssertEqual(parts[1], "三体", "Text 提取失败")
        XCTAssertEqual(parts[2], "abc123", "属性选择器 + 属性名提取失败")
        XCTAssertEqual(parts[3], "https://v.example.com/tv/2/", "baseUrl 相对拼接错误: \(parts[3])")
        XCTAssertEqual(parts[4], "https://cdn.example.com/tv1.jpg", "绝对地址应直通: \(parts[4])")
    }

    // MARK: - 垫片组（判定 C 的重跑）

    func testShimmed_C1() {
        let (_, result) = U01Probe.load(shimmed: true)
        guard case .ok = result else {
            XCTFail("垫片后仍装载失败 → 判定 B（需宿主 Swift 解析层）: \(result)")
            return
        }
    }

    func testShimmed_C2ToC5() throws {
        let (context, load) = U01Probe.load(shimmed: true)
        guard case .ok = load else { throw XCTSkip("垫片组 C-1 未通过 → 判定 B") }
        guard installDriver(context) else {
            XCTFail("pdfh.driver.js 注入失败")
            return
        }
        context.setObject(fixtureHTML(), forKeyedSubscript: "html" as NSString)
        let out = context.evaluateScript("""
        (function(){
            var $ = cheerio.load(html);
            var c2 = $('.detail h1').text();
            var c3 = $('li.item:eq(0) a').attr('title');
            var c4 = typeof $.html($('div.detail'));
            var c5 = pd(html, 'body&&ul.stui-vodlist&&li:eq(1)&&a.pic&&href', 'https://v.example.com');
            return [c2, c3, c4, c5].join('\\u0001');
        })()
        """)?.toString() ?? ""
        let parts = out.components(separatedBy: "\u{0001}")
        XCTAssertEqual(parts.count, 4, "返回结构异常: \(out)")
        XCTAssertEqual(parts[0], "三体")
        XCTAssertEqual(parts[1], "国产剧")
        XCTAssertEqual(parts[2], "string")
        XCTAssertEqual(parts[3], "https://v.example.com/tv/2/")
    }
}
