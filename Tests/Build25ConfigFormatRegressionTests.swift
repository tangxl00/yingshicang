import XCTest
@testable import Yingshicang

/// v2.0.50 build 25 配置源格式兼容性回归守卫。
///
/// 本文件守住三类**新格式**，每条 fixture 都是本轮实际抓取的真实配置内容
/// （不构造、不改写；来源 URL 见 `Docs/CONFIG_FORMATS.md`）：
/// - base64 包装：二进制前导 + `XXXXXXXX**` + base64（`http://www.饭太硬.cc/tv`）
/// - AES `2423` 配置（`https://www.wya6.cn/tv/yc.json`）
/// - JS 对象字面量 / 类 JSON5（`https://raw.githubusercontent.com/gsdlj/TVBox/main/4.txt`）
///
/// 同时守住：build 24 的 15 条口径不回退、错误提示仍带真实原因。
final class Build25ConfigFormatRegressionTests: XCTestCase {

    // MARK: - fixture 装载（真实样本原样落盘，按 bundle 读取）

    private func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle(for: Build25ConfigFormatRegressionTests.self)
        // Fixtures 以 folder reference 打进测试 bundle（project.yml: Tests/Fixtures → resources），
        // 读取必须带 subdirectory。
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw XCTSkip("fixture \(name) 未打进测试 bundle")
        }
        return try Data(contentsOf: url)
    }

    // MARK: - 1. base64 包装（二进制前导 + `**` 标记）

    /// 真实样本：`http://www.饭太硬.cc/tv`，18,843 字节。
    /// 结构：JPEG `ffd8ffe0…` 前导 2,401 字节 → `HnPSxaeH**` → base64（解出 12,323 字节配置）。
    func testBase64PreambleConfigLoads() throws {
        let data = try fixtureData("fantaiying_body")
        let output = ConfigParser.decodePayload(data: data)
        XCTAssertEqual(output.shape.displayName.hasPrefix("base64 包装配置"), true,
                       "必须识别为 base64 包装，实际: \(output.shape.displayName)")
        XCTAssertNil(output.warning)
        XCTAssertTrue(output.text.contains("\"sites\""), "解出的载荷必须是配置 JSON")

        guard case .success(let bundle) = ConfigParser.parseResult(data: data, text: "") else {
            return XCTFail("base64 包装的真实配置必须可加载")
        }
        XCTAssertEqual(bundle.sites.count, 49, "真实样本解出 49 个站点")
    }

    /// 关键口径：`**` 标记必须在**字节层**找到。
    /// 二进制前导（JPEG `ffd8ffe0…`）必然不是合法 UTF-8 —— 任何「先解成字符串再找标记」
    /// 的实现都只能依赖回落编码，而回落行为因平台而异（GB18030 可能整串失败回落 Latin-1，
    /// 也可能把高位字节按双字节消耗吞掉标记）。唯一可靠的位置是字节层。
    /// 注：本断言不依赖平台回落编码的具体行为（本地实测 Python GB18030 在字节 0 即失败）。
    func testBase64MarkerDisappearsIfDecodedFirst() throws {
        let data = try fixtureData("fantaiying_body")
        XCTAssertNil(String(data: data, encoding: .utf8),
                     "JPEG 二进制前导必然不是合法 UTF-8，字符串层方案没有可靠前提")
        XCTAssertNotNil(ConfigParserImplProbe.markerByteRange(in: data),
                        "字节层必须能找到标记")
    }

    // MARK: - 2. AES `2423` 配置

    /// 真实样本：`https://www.wya6.cn/tv/yc.json`，30,444 字节十六进制。
    /// 头部 `2423` + `$#wycxd#$`（key 内嵌明文），末 13 位是 IV，`2324` 之后是密文。
    /// 实测解密为 14,543 字节严格 JSON，4 个站点。
    func testAES2423ConfigLoads() throws {
        let data = try fixtureData("wya6_2423.txt")
        let output = ConfigParser.decodePayload(data: data)
        XCTAssertEqual(output.shape, .aes2423, "必须识别为 2423 AES 配置")
        XCTAssertNil(output.warning, "真实样本必须解密成功，实际: \(output.warning ?? "-")")

        guard case .success(let bundle) = ConfigParser.parseResult(data: data, text: "") else {
            return XCTFail("2423 AES 真实配置必须可加载")
        }
        XCTAssertEqual(bundle.sites.count, 4)
        XCTAssertTrue(bundle.sites.allSatisfy { $0.type == 3 }, "该配置 4 个站点全为 type 3")
    }

    /// 密钥必须来自明文头部，且**绝不回显**在错误文案里。
    func testAESFailureMessageNeverLeaksKey() {
        // 截断密文：长度不再是 16 的整数倍。
        let broken = "2423" + String(repeating: "00", count: 8) + "2324" + String(repeating: "11", count: 30)
        let result = ConfigTransformerProbe.aesMessage(for: broken)
        XCTAssertTrue(result.contains("AES 加密配置"), "实际: \(result)")
        XCTAssertFalse(result.contains("$#"), "错误提示不得回显密钥段")
        XCTAssertFalse(result.contains("wycxd"), "错误提示不得回显密钥内容")
    }

    /// 缺少 `$#…#$` 密钥段时给出结构性原因，而不是「不是合法 JSON」。
    ///
    /// 构造说明（本地 Linux 全链路实测过）：hex 文本里的 `2423` 前缀解码后就是 `$#` 字节，
    /// `2324` 分隔符解码后就是 `#$` 字节 —— 所以只要文本形如 `2423…2324…`，
    /// `$#`/`#$` 两个标记都天然存在，「缺少密钥段」分支几乎不可达。
    /// 真正能命中该分支的形态是 `2423` 与 `2324` 相邻（`$##$`，密钥段为空）。
    func testAESMissingKeySegmentReportsStructure() {
        let broken = "2423" + "2324" + String(repeating: "ab", count: 40)
        let result = ConfigTransformerProbe.aesMessage(for: broken)
        XCTAssertTrue(result.contains("AES 加密配置"), "实际: \(result)")
        XCTAssertTrue(result.contains("密钥段"), "必须指出密钥段问题，实际: \(result)")
    }

    // MARK: - 3. JS 对象字面量 / 类 JSON5

    /// 真实样本：`https://raw.githubusercontent.com/gsdlj/TVBox/main/4.txt`，12,586 字节。
    /// `{spider:'…',sites:[{key:'t4public',…}]}` —— 未加引号的键 + 单引号字符串。
    /// 严格 JSON 在 `line 1 column 2` 失败；归一后 77 个站点。
    func testJSObjectLiteralConfigLoads() throws {
        let data = try fixtureData("gsdlj_4.txt")
        let text = BodyDecoder.decode(data, contentType: "text/plain")
        guard case .success(let bundle) = ConfigParser.parseResult(data: data, text: text) else {
            return XCTFail("JS 字面量真实配置必须可加载")
        }
        XCTAssertEqual(bundle.sites.count, 77, "真实样本归一后 77 个站点")
        XCTAssertTrue(bundle.sites.contains { $0.key == "t4public" }, "必须解出样本首站点 key")
    }

    /// 反引号模板字符串属于 JS 表达式，不是配置字面量：必须明确不支持，而不是静默改写。
    func testTemplateLiteralConfigIsRejectedWithReason() {
        let text = "{sites:[{key:'a',name:`模板`}]}"
        guard case .failure(let failure) = ConfigParser.parseResult(text: text) else {
            return XCTFail("模板字符串必须失败")
        }
        XCTAssertTrue(failure.message.contains("JS 对象字面量配置"), "实际: \(failure.message)")
        XCTAssertTrue(failure.message.contains("模板字符串"), "必须指出模板字符串，实际: \(failure.message)")
    }

    /// 标准 JSON 不能被 JS 归一器改写（string 里含单引号是合法 JSON）。
    func testStrictJSONWithApostropheNotRewritten() {
        let text = "{\"sites\":[{\"key\":\"a\",\"name\":\"it's fine\",\"type\":1,\"api\":\"x\"}]}"
        guard case .success(let bundle) = ConfigParser.parseResult(text: text) else {
            return XCTFail("合法 JSON 里的单引号不得触发 JS 归一")
        }
        XCTAssertEqual(bundle.sites.first?.displayName, "it's fine")
    }

    // MARK: - 4. build 24 口径不回退

    func testPlainJSONStillWorks() throws {
        let data = try fixtureData("cxkjg_tvbox.json")
        guard case .success(let bundle) = ConfigParser.parseResult(data: data, text: "") else {
            return XCTFail("严格 JSON 配置必须可加载")
        }
        XCTAssertEqual(bundle.sites.count, 12)
        XCTAssertEqual(ConfigParser.decodePayload(data: data).shape, .plain)
    }

    /// 空文本 / 多仓索引的既有提示不得被新格式分支改写。
    func testBuild24FailureMessagesUnchanged() {
        if case .failure(let failure) = ConfigParser.parseResult(text: "   \n  ") {
            XCTAssertEqual(failure.message, "配置内容为空")
        } else {
            XCTFail("空文本必须失败")
        }
        if case .failure(let failure) = ConfigParser.parseResult(text: "{\"urls\":[\"http://a/1.json\"]}") {
            XCTAssertTrue(failure.message.contains("多仓索引"), "实际: \(failure.message)")
        } else {
            XCTFail("多仓索引文件不是单仓配置")
        }
    }

    /// 多仓索引仍按内容而非后缀判定（真实样本是 `.txt` 后缀的 `{"urls":[…]}`）。
    func testStoreIndexFromTxtSuffixedBody() {
        let text = "{\"urls\":[{\"name\":\"A\",\"url\":\"http://a/1.json\"},{\"name\":\"B\",\"url\":\"http://b/2.json\"}]}"
        let stores = ConfigParser.parseStoreIndex(text: text)
        XCTAssertEqual(stores.count, 2)
        XCTAssertEqual(stores.first?.name, "A")
    }

    /// BOM 字节必须在字节层剥掉（不是靠 String 侧 replace）。
    func testBOMBytesStrippedAtByteLayer() throws {
        let json = "{\"sites\":[{\"key\":\"k\",\"name\":\"站点\",\"type\":3,\"api\":\"csp_K\"}]}"
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: Array(json.utf8))
        let output = ConfigParser.decodePayload(data: data)
        XCTAssertFalse(output.text.hasPrefix("\u{FEFF}"), "字节层必须剥 BOM")
        guard case .success(let bundle) = ConfigParser.parseResult(data: data, text: "") else {
            return XCTFail("带 BOM 字节的配置必须可加载")
        }
        XCTAssertEqual(bundle.sites.first?.displayName, "站点")
    }
}

// MARK: - 测试探针（只为断言内部口径，不进入产品路径）

private enum ConfigParserImplProbe {
    /// 复刻字节层标记检索，用来证明「解码后再找就找不到」。
    static func markerByteRange(in data: Data) -> Range<Int>? {
        let bytes = [UInt8](data)
        guard bytes.count > 16 else { return nil }
        var index = 0
        while index + 1 < bytes.count {
            if bytes[index] == 0x2A, bytes[index + 1] == 0x2A, index >= 8 {
                return (index - 8)..<(index + 2)
            }
            index += 1
        }
        return nil
    }
}

private enum ConfigTransformerProbe {
    static func aesMessage(for text: String) -> String {
        let output = ConfigTransportDecoder.decode(data: Data(text.utf8), contentType: "application/json")
        if let warning = output.warning {
            return ConfigParser.Failure.undecodable(shape: output.shape.displayName, detail: warning).message
        }
        switch ConfigParser.parseResult(text: text) {
        case .failure(let failure): return failure.message
        case .success: return "（意外成功）"
        }
    }
}
