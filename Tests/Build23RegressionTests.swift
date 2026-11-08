import XCTest
@testable import Yingshicang

/// v2.0.50 build 23 新增能力回归守卫。
///
/// 覆盖（每条可证伪，缺实现必失败）：
/// 1. 扫码 URL 校验 —— ConfigRepository.acceptableConfigURL 白名单（http/https + 非空 host）
/// 2. F-09 播放内核路由 —— PlaybackRouter 注入式判定（vlcAvailable 真假 × 容器/avPlayable 组合）
/// 3. aliToken 凭证安全 —— 明文不出现在 UserDefaults / 迁移 / resetAll 清理（Keychain 不可用环境降级断言）
/// 4. F-20 下载落盘支撑 —— sanitizedName / stableHash 稳定性 / assess 三分支 / fileName 口径
/// 5. R-39 网盘 —— OAuth 授权 URL 构造 / AliDriveFile 宽容解码
/// 6. WebDAV 明文 HTTP 一次性提示 —— isPlaintextHTTP 判定
/// 7. 屏蔽源过滤接缝 —— searchableSites 已在 Build22Batch2 覆盖（此文件不重复）
final class Build23RegressionTests: XCTestCase {

    // MARK: - 1. 扫码 URL 校验（范围二 · 安全收尾）

    /// acceptableConfigURL：仅放行 http/https 且 host 非空的地址，其余一律拒绝。
    func testAcceptableConfigURLWhitelist() {
        // 合法：http / https + 域名、IP、带端口、带路径。
        XCTAssertNotNil(ConfigRepository.acceptableConfigURL(from: "https://config.example.com/index.json"))
        XCTAssertNotNil(ConfigRepository.acceptableConfigURL(from: "http://192.168.1.8:9978/config"))
        XCTAssertEqual(ConfigRepository.acceptableConfigURL(from: "  https://a.example.com/c.json\n")?.host,
                       "a.example.com", "首尾空白必须被剔除")

        // 非法：非 http(s) scheme。
        XCTAssertNil(ConfigRepository.acceptableConfigURL(from: "ftp://files.example.com/config.json"),
                     "ftp 不在白名单")
        XCTAssertNil(ConfigRepository.acceptableConfigURL(from: "file:///etc/passwd"), "file 必须拒绝")
        XCTAssertNil(ConfigRepository.acceptableConfigURL(from: "data:text/html,<script>"),
                     "data 必须拒绝（防扫码注入本地页面）")
        XCTAssertNil(ConfigRepository.acceptableConfigURL(from: "javascript:alert(1)"), "javascript 必须拒绝")

        // 非法：无 scheme / 无 host / 空串。
        XCTAssertNil(ConfigRepository.acceptableConfigURL(from: "config.example.com/index.json"),
                     "无 scheme 的裸域名必须拒绝")
        XCTAssertNil(ConfigRepository.acceptableConfigURL(from: "https://"), "无 host 必须拒绝")
        XCTAssertNil(ConfigRepository.acceptableConfigURL(from: ""), "空串必须拒绝")
        XCTAssertNil(ConfigRepository.acceptableConfigURL(from: "   "), "纯空白必须拒绝")
    }

    // MARK: - 2. F-09 播放内核路由

    /// 路由决策：vlcAvailable 为入参（可注入假探测），不依赖 CI 是否真的装了 VLCKit。
    func testPlaybackRouterInjectableDecisions() {
        let vlcOn = PlaybackRouter(vlcAvailable: true)
        let vlcOff = PlaybackRouter(vlcAvailable: false)

        // mkv 等容器：有 VLC 走 VLC，没有先试 AVPlayer（明确 reason）。
        XCTAssertEqual(vlcOn.engine(forContainerExtension: "mkv").engine, .vlc,
                       "mkv 不在 AVFoundation 支持范围，集成 VLCKit 时必须走 VLC")
        XCTAssertEqual(vlcOff.engine(forContainerExtension: "mkv").engine, .avplayer,
                       "未集成 VLCKit 时降级 AVPlayer 尝试，不得崩溃")
        XCTAssertTrue(vlcOff.engine(forContainerExtension: "mkv").reason.contains("未集成"),
                      "降级路径的 reason 必须如实说明未集成")

        // 后缀大小写与前置点必须归一。
        XCTAssertEqual(vlcOn.engine(forContainerExtension: ".MKV").engine, .vlc)
        XCTAssertEqual(vlcOn.engine(forContainerExtension: "RmVb").engine, .vlc)

        // AVFoundation 原生容器与 HLS 走 AVPlayer。
        XCTAssertEqual(vlcOn.engine(forContainerExtension: "mp4").engine, .avplayer)
        XCTAssertEqual(vlcOn.decision(for: URL(string: "https://x.example.com/a.m3u8")!).engine, .avplayer,
                       "HLS 清单是 AVPlayer 原生强项，即使集成 VLC 也优先 AVPlayer")
    }

    /// avPlayable 兜底链：AVAsset 判不可播（如 mp4 封装 DTS 音轨）→ 回退 VLC；
    /// 未集成时只能留在 AVPlayer 并如实报告。
    func testPlaybackRouterAvPlayableFallback() {
        let vlcOn = PlaybackRouter(vlcAvailable: true)
        let vlcOff = PlaybackRouter(vlcAvailable: false)
        let mp4 = URL(string: "https://x.example.com/movie.mp4")!

        // 未做可播性实测（nil）→ 按容器直接给结论。
        XCTAssertEqual(vlcOn.decision(for: mp4, avPlayable: nil).engine, .avplayer)
        // 实测可播 → AVPlayer。
        XCTAssertEqual(vlcOn.decision(for: mp4, avPlayable: true).engine, .avplayer)
        // 实测不可播 → VLC 兜底；未集成 VLC → 留 AVPlayer 且 reason 说明。
        XCTAssertEqual(vlcOn.decision(for: mp4, avPlayable: false).engine, .vlc,
                       "AVAsset 判不可播必须触发 VLC 兜底")
        XCTAssertEqual(vlcOff.decision(for: mp4, avPlayable: false).engine, .avplayer)
        XCTAssertTrue(vlcOff.decision(for: mp4, avPlayable: false).reason.contains("未集成"))
    }

    // MARK: - 3. aliToken 凭证安全（范围二 · P2 收尾）

    /// 核心安全性质（不依赖 Keychain 是否可用）：Token 明文永不落 UserDefaults，
    /// getter 永不读 UserDefaults。与 webDavPassword 的 CredentialStorageTests 同范式。
    func testAliTokenNeverTouchesUserDefaults() {
        let legacyKey = "tpc_settings.aliToken"
        defer {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            Settings.shared.aliToken = ""
        }

        // ① 写入路径：设置 Token 后 UserDefaults 里不得出现明文与旧键。
        let token = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
        Settings.shared.aliToken = token
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            if let text = value as? String {
                XCTAssertFalse(text.contains(token),
                               "Token 明文出现在 UserDefaults 键 \(key)，凭证必须存 Keychain")
            }
            XCTAssertFalse(key.hasSuffix("aliToken") && !key.contains("ClientID"),
                           "UserDefaults 不应存在 aliToken 键（实际键：\(key)）")
        }

        // ② 读取路径：往旧键写诱饵。Keychain 可用环境 getter 直接读 Keychain（迁移早完成）；
        //    无 Keychain entitlement 环境（CI 未签名构建）getter 走一次性迁移、把旧明文值
        //    原样交还一次——这是「升级不丢 Token」的设计。两种环境下都必须成立的性质是：
        //    触碰后旧明文副本被删除，且再次读取不再回到 UserDefaults 明文。
        UserDefaults.standard.set("plaintext-decoy-token", forKey: legacyKey)
        _ = Settings.shared.aliToken
        XCTAssertNil(UserDefaults.standard.string(forKey: legacyKey),
                     "getter 触碰后 UserDefaults 明文副本必须被清除")
        XCTAssertNotEqual(Settings.shared.aliToken, "plaintext-decoy-token",
                          "明文副本清除后 getter 不得再读到 UserDefaults 明文")
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    /// 一次性迁移：旧版 UserDefaults 明文在首次读取时搬走并删除原键。
    /// Keychain 可用与不可用两种环境下，「原键被清」都必须成立（迁移必删明文副本）。
    func testAliTokenLegacyMigrationRemovesPlaintext() {
        let legacyKey = "tpc_settings.aliToken"
        defer {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            Settings.shared.aliToken = ""
        }
        Settings.shared.aliToken = ""
        UserDefaults.standard.set("legacy32token000000000000000000ab", forKey: legacyKey)

        let migrated = Settings.shared.aliToken
        XCTAssertEqual(migrated, "legacy32token000000000000000000ab",
                       "迁移必须把旧明文值原样交还（升级不丢 Token）")
        XCTAssertNil(UserDefaults.standard.string(forKey: legacyKey),
                     "迁移完成后 UserDefaults 明文副本必须删除")
    }

    /// resetAll 必须清掉 Keychain 里的 aliToken（Keychain 不可用环境显式 skip，不伪造通过）。
    func testResetAllClearsAliToken() throws {
        Settings.shared.aliToken = "resetprobe00000000000000000000ff"
        guard Settings.shared.aliToken == "resetprobe00000000000000000000ff" else {
            Settings.shared.aliToken = ""
            throw XCTSkip("当前环境无 Keychain entitlement，跳过 resetAll 清理验证")
        }
        Settings.shared.resetAll()
        XCTAssertEqual(Settings.shared.aliToken, "", "重置 App 后 Token 必须从 Keychain 清除")
    }

    // MARK: - 4. F-20 下载落盘支撑（DownloadSupport 纯函数）

    /// 文件名净化：非法字符替换、空白剔除、超长截断、空串兜底。
    func testDownloadSanitizedName() {
        XCTAssertEqual(DownloadSupport.sanitizedName("正常片名"), "正常片名")
        XCTAssertEqual(DownloadSupport.sanitizedName("a/b\\c:d*e?f\"g<h>i|j"), "a_b_c_d_e_f_g_h_i_j",
                       "路径非法字符必须替换为下划线")
        XCTAssertEqual(DownloadSupport.sanitizedName("  \n\t "), "未命名", "纯空白必须兜底为「未命名」")
        let long = String(repeating: "长", count: 200)
        XCTAssertEqual(DownloadSupport.sanitizedName(long).count, 80, "超长文件名截断到 80 字符")
    }

    /// stableHash：FNV-1a 稳定哈希——同输入同输出（跨进程可重复，续传落同名文件的前提），
    /// 不同输入不同输出、不等于进程随机的 hashValue。
    func testDownloadStableHashDeterministic() {
        let a1 = DownloadSupport.stableHash("task-A")
        let a2 = DownloadSupport.stableHash("task-A")
        let b = DownloadSupport.stableHash("task-B")
        XCTAssertEqual(a1, a2, "同一输入必须得到同一哈希（断点续传同名文件的前提）")
        XCTAssertNotEqual(a1, b, "不同输入必须可区分")
        XCTAssertFalse(a1.isEmpty)
    }

    /// assess 三分支：m3u8 显式不支持（含 query/大小写形态）、非 http(s) 无效、其余直链。
    func testDownloadAssessThreeBranches() {
        // m3u8（含非常规形态）→ 显式声明不支持，不得伪装成可下载。
        XCTAssertEqual(DownloadSupport.assess("https://x.example.com/a/index.m3u8"), .hlsUnsupported)
        XCTAssertEqual(DownloadSupport.assess("https://x.example.com/a.M3U8"), .hlsUnsupported)
        // 非 http(s) → invalid。
        XCTAssertEqual(DownloadSupport.assess("ftp://x.example.com/a.mp4"), .invalid)
        XCTAssertEqual(DownloadSupport.assess("file:///local/a.mp4"), .invalid)
        XCTAssertEqual(DownloadSupport.assess(""), .invalid)
        XCTAssertEqual(DownloadSupport.assess("不是地址"), .invalid)
        // 普通 http(s) 直链 → direct。
        if case .direct(let url) = DownloadSupport.assess("https://x.example.com/a/第01集.mp4 ") {
            XCTAssertEqual(url.host, "x.example.com")
        } else {
            XCTFail("http 直链必须判定为 direct")
        }
    }

    /// 落盘文件名口径：`片名 - 集名-<稳定哈希>.ext`，非法字符已净化，ext 缺省 mp4。
    func testDownloadFileNameContract() {
        let task = DownloadTask(id: "s1|v1|https://x.example.com/e1", vodId: "v1", vodName: "斗罗/大陆",
                                vodPic: "", siteKey: "s1", episodeName: "第1集",
                                episodeURL: "https://x.example.com/e1", flag: "线路1",
                                status: .pending, createdAt: 0, message: "")
        let name = DownloadSupport.fileName(for: task, extension: "mp4")
        XCTAssertTrue(name.hasPrefix("斗罗_大陆 - 第1集-"), "文件名必须是「净化片名 - 集名-哈希」形态，实际：\(name)")
        XCTAssertTrue(name.hasSuffix(".mp4"))
        XCTAssertEqual(DownloadSupport.fileName(for: task, extension: ""),
                       DownloadSupport.fileName(for: task, extension: "mp4"),
                       "ext 为空时缺省 mp4")
        // 同任务多次生成同名（续传落同一个文件）。
        XCTAssertEqual(name, DownloadSupport.fileName(for: task, extension: "mp4"))
    }

    // MARK: - 5. R-39 网盘（OAuth URL 构造 / 文件模型解码）

    /// 授权 URL：给定 client_id 时产出结构正确的 URL；未配置或 redirectURI 无 scheme 时返回 nil。
    func testAliDriveAuthorizeURL() {
        let url = AliDriveAuth.authorizeURL(clientID: "cid-123",
                                             redirectURI: "https://callback.example.com/cb")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.host, "openapi.alipan.com")
        XCTAssertEqual(url?.path, "/oauth/authorize")
        let query = url?.query ?? ""
        XCTAssertTrue(query.contains("client_id=cid-123"))
        XCTAssertTrue(query.contains("response_type=code"), "开放平台只支持 code 流程")
        XCTAssertTrue(query.contains("redirect_uri="))

        XCTAssertNil(AliDriveAuth.authorizeURL(clientID: "  ", redirectURI: "https://c.example.com"),
                     "未配置 Client ID 不得产出授权 URL（界面应提示手动粘贴 Token）")
        XCTAssertNil(AliDriveAuth.authorizeURL(clientID: "cid", redirectURI: "callback-no-scheme"),
                     "redirectURI 无 scheme 不得产出授权 URL")
    }

    /// AliDriveFile 宽容解码：蛇形命名映射 + 未知键容忍（真实响应多字段不报错）。
    func testAliDriveFileDecoding() throws {
        let json = #"""
        {"file_id":"f1","parent_file_id":"root","name":"电影","type":"folder",
         "size":0,"url":"","unknown_future_field":{"x":1},"category":"video"}
        """#
        let file = try JSONDecoder().decode(AliDriveFile.self, from: Data(json.utf8))
        XCTAssertEqual(file.fileId, "f1")
        XCTAssertEqual(file.parentId, "root")
        XCTAssertEqual(file.name, "电影")
        XCTAssertTrue(file.isFolder, "type=folder 必须判定为目录")

        let fileJSON = #"{"file_id":"f2","name":"a.mp4","type":"file","size":1024}"#
        let plain = try JSONDecoder().decode(AliDriveFile.self, from: Data(fileJSON.utf8))
        XCTAssertFalse(plain.isFolder)
        XCTAssertEqual(plain.size, 1024)
    }

    // MARK: - 6. WebDAV 明文 HTTP 判定（范围二 · P2 收尾）

    func testIsPlaintextHTTP() {
        XCTAssertTrue(WebDavConnectionTester.isPlaintextHTTP("http://192.168.1.8:5005"),
                      "http 直连属明文，必须触发一次性提示")
        XCTAssertTrue(WebDavConnectionTester.isPlaintextHTTP("  HTTP://Example.com  "),
                      "大小写与空白归一后仍是明文")
        XCTAssertFalse(WebDavConnectionTester.isPlaintextHTTP("https://dav.example.com"),
                       "https 加密连接不需要提示")
        XCTAssertFalse(WebDavConnectionTester.isPlaintextHTTP("ftp://x"), "非 http(s) 不属本判定")
        XCTAssertFalse(WebDavConnectionTester.isPlaintextHTTP("192.168.1.8:5005"),
                       "无 scheme 的裸地址由连接测试器另行归一，这里不误报")
        XCTAssertFalse(WebDavConnectionTester.isPlaintextHTTP(""))
    }
}
