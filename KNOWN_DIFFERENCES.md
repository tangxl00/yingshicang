# 已知平台差异与设计决策

记录 iOS 重写相对 Android 2.0.50 原版的已知差异、降级口径与默认取值。U-01 判定结果以 CI 首跑 build-logs 为准回填。

## U-01 前置门判定（cheerio on JavaScriptCore）

- **探针位置**：`U01Gate/Tests/U01GateTests/U01CheerioProbeTests.swift`，跑 macOS（非模拟器）
- **五条断言**：C-1 无异常装载 / C-2 可构造 DOM / C-3 选择器（`:eq`、属性选择器）命中 / C-4 `$.html(node)` 返回字符串 / C-5 真实 `pdfh` 链式调用含 `:eq`、属性提取与 baseUrl 拼接
- **垫片对照组**：仅注入最小 Node 垫片（`global` / `process` / `Buffer` 的类型与编码），不补任何 DOM 能力
- **判定**：
  - [x] **A** — 两组全绿，维持 JavaScriptCore 原设计
  - [ ] **C** — 原生组失败、垫片组全绿，注入最小垫片重跑
  - [ ] **B** — 两组均失败，降级为宿主 Swift 实现 `pdfh/pdfa/pd`（`Core/Parsing/` 已有备胎实现）

**首跑结果：判定 A**（run `42318808457`，job「U-01 cheerio gate (macOS)」）

- 真实 `swift test` 输出（读 build-logs / job logs，非仅看 conclusion）：`Executed 7 tests, with 0 failures`，`Test Suite 'All tests' passed`
- 原生组 5 条断言全绿：`testC1_LoadWithoutException` / `testC2_ConstructDOM` / `testC3_SelectorHit` / `testC4_HtmlReturnsString` / `testC5_RealPdfhCall`
- 垫片对照组 2 条全绿：`testShimmed_C1` / `testShimmed_C2ToC5`
- **结论**：JavaScriptCore + cheerio.bundle 路线在 macOS 原生环境成立，**维持「JS 引擎 + cheerio」原设计**；不注入最小垫片、不降级到宿主 Swift 实现 `pdfh/pdfa/pd`。备胎实现（`Core/Parsing/HTML/`）保留在仓库中作为非 JS 站点解析路径，不是 U-01 的替代方案。
- 首跑期间修掉的两处探针缺陷（均属本地可复现，已在 `node --check` 与本地 JS 验证）：① `pdfh.driver.js` 内 `/^https?:\\/\\//i` 正则转义错误导致注入 SyntaxError；② `pdfh`/`pdfa` 的 `body`/`html` 段语义应为「文档根」而非「后代选择器」，否则 C-5 取值全空。

## 平台级不支持

| 差异 | 说明 | 用户可见行为 |
| --- | --- | --- |
| jar 型站点 | iOS 无 JVM，无法运行 Java 爬虫扩展 | 站点列表标注「jar·iOS 不支持」，进入站点显式提示，不静默失败 |
| VLC 播放内核 | MobileVLCKit 无官方 SPM 分发，采用 `canImport` 编译期探测 | 未集成时选择 VLC 内核会明确报错「当前构建未集成 VLC 内核」，不静默降级 |
| 本地视频导入 | iOS 沙箱限制，无法像 Android 一样扫描文件系统 | 「本地数据」页说明受限 |
| 应用内自更新 | App Store / 企业签分发模型下无 Android 式自更新通道 | 「检查更新」页说明 iOS 无自更新通道 |
| DLNA 投屏 / P2P | 未在本版实现 | 不展示对应入口 |
| 互动交流 | 未接入 H5 互动页 | 占位说明页 |

## 按用户要求移除的功能（v2.0.50 build 21）

以下能力**不是缺失，是用户在真机验收后明确要求移除**的（2026-11 验收反馈原话：
「去掉短视频功能，去掉直播功能」）。自 build 21 起源码中不再存在对应实现：

| 功能 | 原实现 | 移除方式 |
| --- | --- | --- |
| 短视频（WKWebView 流） | `Features/ShortVideo/` + Tab 入口 | 整目录删除，Tab 5 → 3（主页 / 历史·收藏 / 我的） |
| 直播页 / 直播设置 / 频道弹窗 / 直播控制 | `Features/Live/` + `LiveParser` + `Settings.liveTimeout` 等 | 整目录删除，设置键与 DesignTokens 直播度量一并清理 |

配套口径：配置文件里的 `lives` 字段自 build 21 起不再纳入模型（`ConfigBundle` 无 `lives` 属性），
Codable 将其作为未知键静默跳过——**加载含 `lives` 的配置不会报错**，由
`Build21RegressionTests.testRealTop98ConfigIgnoresLives` 用真实 top98.json 结构固化。

## 默认取值（对齐 Android 实测）

- 主色 `main = #00C64E`，主背景 `mainBg = #001A37`（ARGB 实测自 APK resources.arsc）
- 持久化键名：`tpc_stores` / `tpc_current_line` / `tpc_settings.*` / `tpc_search_history`（UserDefaults；数据库表 favorite / history / lanDevice / blockedSite 对齐 Room）
- 站点 type 路由：0=HTML 解析、1=JSON API、3=JS 爬虫；`csp_` 前缀按 API 处理；jar → Unsupported
- 搜索参与条件：`searchable > 0` 且非 jar 且未被用户屏蔽；聚合线程数取 `searchThreadCount`（上限 8）
- dp→pt 按 1:1 换算（160dpi 基准），全部经 `DesignTokens/Metrics` 统一驱动

## 隐私声明 / ATS / 后台音频的取值口径（质检 P2-2）

原则：**声明与实现必须一一对应，不做「先声明后实现」的预留；做不到的一律删声明**。三类项分别取不同结论：

| 项目 | 原状态 | 处理 | 理由 |
| --- | --- | --- | --- |
| `NSCameraUsageDescription` | 已声明 | **删除** | 全仓 0 处 `AVCaptureDevice` / 相机相关调用，本版无扫码、无拍摄功能 |
| `NSPhotoLibraryUsageDescription` | 已声明 | **删除** | 0 处 `PHPhotoLibrary` / `UIImagePickerController`；封面保存走网络下载到沙箱，不写相库 |
| `NSPhotoLibraryAddUsageDescription` | 已声明 | **删除** | 同上，无相库写入路径 |
| `NSMicrophoneUsageDescription` | 已声明 | **删除** | 0 处 `AVAudioRecorder` / `AVAudioSession` 录音类别；本版无录音、无语音搜索 |
| `NSLocalNetworkUsageDescription` | 已声明 | **删除** | 本版无 DLNA 投屏、无局域网设备发现；WebDAV 为用户手填地址，不需要本地网络权限扫描 |
| `NSBonjourServices`（3 项 `_http._tcp` 等） | 已声明 | **删除** | 同上，无 Bonjour 浏览实例 |
| `UIBackgroundModes = audio` | 已声明但无实现 | **补实现**（保留声明） | 视频播放器切后台继续出声是播放器的基本行为，删声明会造成功能缺陷；已在 `AppDelegate` 的 `configureAudioSession()` 里设置 `AVAudioSession` `.playback` 类别 + `.moviePlayback` 模式并 `setActive(true)`，声明与实现对齐 |

**ATS 口径**：`NSAppTransportSecurity` 下**只保留 `NSAllowsArbitraryLoads = true` 这一个键**（采集站与配置源大量使用明文 HTTP，与 Android 原版行为一致）。⚠️ Apple 规则：iOS 10+ 上只要同 dict 里出现 `NSAllowsArbitraryLoadsInWebContent` / `NSAllowsArbitraryLoadsForMedia` / `NSAllowsLocalNetworking` 任何一个，`NSAllowsArbitraryLoads` 就被忽略并按 NO 处理——build 20 曾因多写了 `InWebContent` 导致全部明文 HTTP 被平台层拦截（NSURLError -1022），配置拉取全部失败且被上层伪装成「HTTP 500」，build 21 已修复并加注释固化。明文请求的越权风险由 `JSRequestPolicy` 在 JS 桥 `req` 层逐请求兜底：禁 `file:`/`data:`/`javascript:`/`ftp:` 等危险协议、默认拒绝内网与回环地址、按站点域白名单限制跨站读取（详见「播放解析与 JS 桥安全」一节）明文请求的越权风险由 `JSRequestPolicy` 在 JS 桥 `req` 层逐请求兜底：禁 `file:`/`data:`/`javascript:`/`ftp:` 等危险协议、默认拒绝内网与回环地址、按站点域白名单限制跨站读取（详见「播放解析与 JS 桥安全」一节）。

## 播放解析与 JS 桥安全（质检 P1-1 / P1-4 / P1-5 / P1-6）

三类源（HTML / JSON API / JS 爬虫）的播放解析不再各自为政，统一收敛到 `Core/Parsing/PlayResolver.swift`：

- **管线**：直链快路径 → lazy 规则（三类源一致，含 `js:` 与 `json:` 两种前缀）→ provider 分类 → `parseIndex` 二次解析（取 `parses[]` 对应解析源）→ `needSniff` 页面嗅探。
- **失败语义**：任何一步拿不到可用地址都返回 `.failure` 并带可定位原因；**不再把入参原样当直链返回并宣告成功**（原 `JSPlayParser` 的两处 `return .success(原始地址)` 已随该文件删除）。
- **JS 引擎隔离**：不存在全局单例 `JSEngine.shared`；`JSEngineRegistry` 按 `site:<key>` / `lazy:<key>` 各建独立 `JSContext` 与独立串行队列，8 路并发搜索不会互相覆盖 `__JS_SPIDER__`；同一站点的脚本装载状态记在引擎上（`loadOnce`），只求值一次。
- **Promise**：`callSpider` 对带 `then` 的返回值做真实收敛——挂原生 resolve/reject block 写状态盒、推进 JSC microtask、按 `promiseTimeout` 超时，超时报 `.promiseTimeout`、拒绝报 `.promiseRejected`，二者都是失败。
- **`req` 准入**：`JSRequestPolicy` 先判协议前缀（在归一化之前拦 `data:` 等，防止被补成 `http://data:...` 绕过），再判内网/回环，最后按站点注册域白名单判定。
- **`local` 隔离**：存储键加 `js.local.<scope>.` 前缀，站点之间不共享键空间。
