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
| jar 型站点（`csp_*` / `py_*` / `.jar`） | iOS 无 JVM，无法运行 Java 爬虫扩展 | 站点列表灰显并标注「jar 插件·iOS 不支持」且不可点；默认站点选择跳过它们；即使被选中也会**同步立即**返回「该站点依赖 jar 插件，iOS 不支持」并给「切换站点」入口，绝不无限加载 |
| VLC 播放内核 | build 23 起以 **VLCKit 4.0 官方 SPM 包**集成（`project.yml` pin `4.0.0-a25`，binaryTarget checksum `f37c8dbd…2f1fb`）；动态 framework 嵌入 `Frameworks/VLCKit.framework`，免签 IPA 内未签名属预期，侧载重签工具会整体重签 | mkv/rmvb/flv 等容器与 DTS/AC3 音轨由 VLCKit 真实播放；`PlaybackRouter` 按容器后缀 + AVAsset 可播性路由，失败显式报错不静默降级 |
| 本地视频导入 | iOS 沙箱限制，无法像 Android 一样扫描文件系统 | 「本地数据」页说明受限 |
| 应用内自更新 | App Store / 企业签分发模型下无 Android 式自更新通道 | 「检查更新」页说明 iOS 无自更新通道 |
| DLNA 投屏 / P2P | 未在本版实现 | 不展示对应入口 |
| 应用列表（R-40） | iOS 沙箱无法枚举已安装应用（无 Android PackageManager 等价 API） | 「我的」页不展示应用列表入口 |

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
- 站点路由（build 25 起）：不再按 `type` + 前缀猜，改由 `SiteConfig.spiderKind` 单一事实源判定——`http(s)://…` 非 .js = JSON 接口、`.js`（相对或绝对）= JS 脚本、**裸 Java 类名（`csp_*` / `py_*`）或 `.jar` = jar 类 → Unsupported（iOS 无 JVM）**。真实配置（`raw.liucn.cc/box/m.json`，234 站点）把 jar 包声明在**顶层 `spider`**（`./fty.jar;md5;…`），站点 `api` 只写类名，因此「带 jar 字段才算 jar」的旧口径会漏判 61 个站点——那正是 build 24 首屏无限转圈的成因
- 搜索参与条件：`searchable > 0` 且 `isPlatformSupported`（非 jar 类）且未被用户屏蔽；聚合线程数取 `searchThreadCount`（上限 8）；每个站点的搜索请求都套 20 秒加载守卫
- dp→pt 按 1:1 换算（160dpi 基准），全部经 `DesignTokens/Metrics` 统一驱动

## 隐私声明 / ATS / 后台音频的取值口径（质检 P2-2）

原则：**声明与实现必须一一对应，不做「先声明后实现」的预留；做不到的一律删声明**。三类项分别取不同结论：

| 项目 | 原状态 | 处理 | 理由 |
| --- | --- | --- | --- |
| `NSCameraUsageDescription` | build 21 删除 | **build 22 回填** | 扫码页（R-44）落地：`ScanCodeViewController` 使用 `AVCaptureSession` 扫二维码，声明与实现对齐 |
| `NSLocalNetworkUsageDescription` | build 21 删除 | **build 22 回填** | 局域网同步（R-43/F-18）落地：`BonjourDeviceFinder` 需本地网络权限做设备发现 |
| `NSBonjourServices`（`_yingshicang._tcp`） | build 21 删除 | **build 22 回填，build 23 收敛为仅此一项** | 与 `LANSyncServiceDescriptor.serviceType` 同源；曾一并回填的 `_http._tcp` 在代码中无任何浏览/注册实例，build 23 按「声明与实现一一对应」删除 |
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

## build 22 新增能力与真机复测清单（CI 模拟器无法覆盖的项）

build 22 批次三落地了 R-07/08/31/32/33/42/43/44/48/49/50/54、F-18/F-20、R-39（best-effort）。其中以下能力依赖真实硬件 / 真实局域网，**CI 模拟器只能验证逻辑层与降级路径，行为须真机复测**：

| 能力 | 模拟器已验证 | 需真机确认 |
| --- | --- | --- |
| 扫码（R-44） | 权限分支逻辑、无相机兜底手动输入、2s 冷却常量；build 23 起扫码结果先过 `ConfigRepository.acceptableConfigURL`（http/https + 非空 host）才进加载链路 | 摄像头取流、取景框布局、真实二维码识别率 |
| 摇一摇（R-32） | 合成加速度序列：静止不触发 / 上升沿触发 / 冷却防连触 | CoreMotion 真实传感器阈值手感（2.2 / 1.5s 是否需要按真机调参） |
| 局域网发现（R-43/F-18） | 端点解析、服务类型声明、`Info.plist` 权限键 | Bonjour 真实设备发现（需另一台同网设备广播 `_yingshicang._tcp.`） |
| 局域网推送（R-49）/ TV 互动（R-42） | URL/请求体构造、地址归一化 | 对 TV 端服务的真实联通性（`/sync/push`、`/interaction` 端点由 TV 侧实现） |
| 下载任务（F-20） | 任务模型生命周期、持久化往返、去重；build 23 起直链整文件真实落盘（后台 URLSession + resume data 断点续传 + 进度节流回写）、列表显示文件大小、点击播放本地文件、删除连带清文件 | m3u8 分片合并下载仍不支持（列表里显式标失败并说明）；真实网络吞吐与后台唤醒需真机复测 |

**F-20 边界说明**（build 23 更新）：下载已从「登记层」升级为**真实落盘**——`DownloadService` 用 `URLSessionConfiguration.background` 建 `com.yingshicang.ios.download` 会话，直链（mp4/mkv/ts 等单文件）整文件下载到 `Documents/Downloads/`，暂停走 `cancel(byProducingResumeData:)` 保存续传数据、恢复走 `downloadTask(withResumeData:)`，进度节流写回任务状态。仍不支持的：**m3u8/HLS 分片合并离线**（需要在本地跑拼接管线，属后续版本），此类任务在列表里显式标「m3u8 分片本版不支持」而不是假装下载。

**R-39 网盘边界说明**（build 23 更新）：Token 弹层、Keychain 存取、开放接口客户端（`openFile/list` 文件列表 / `openFile/getDownloadUrl` 直链转发）、H5 授权容器（`WebContainerViewController.authorizing`）与网盘文件浏览页均已落地。接口证据链：`openapi.alipan.com` 各端点 GET→405 / 伪 Bearer→401 `AccessTokenInvalid`，证明端点真实且强制鉴权；**但字段级返回结构未用真实 Token 端到端实测**（沙箱无有效凭据），真实可用性需真机配置 Token 后复测。



## build 25：配置源格式兼容矩阵结论（`Docs/CONFIG_FORMATS.md`）

证据驱动的新格式适配结论（全部基于实际抓取样本，无一条来自推理）：

| 格式 | 结论 | 真实样例 |
| --- | --- | --- |
| base64 包装（二进制前导 + `XXXXXXXX**` + base64） | **已支持**（`ConfigTransportDecoder` 字节层识别） | `http://www.饭太硬.cc/tv`（JPEG 前导 2,401 B + `HnPSxaeH**`） |
| AES `2423` 配置（密钥内嵌明文头部） | **已支持**（AES-128-CBC/PKCS7，CommonCrypto） | `https://www.wya6.cn/tv/yc.json`（30,444 B 十六进制） |
| JS 对象字面量 / 类 JSON5（裸键 + 单引号） | **已支持**（`JSON5Lite` 归一为标准 JSON） | `https://raw.githubusercontent.com/gsdlj/TVBox/main/4.txt` |
| 口令型加密配置 | **不支持（未发现真实样本）**：APK 字符串表 `密码/口令/密钥/加密/2423` 全部 0 命中，FongMi `Decoder#cbc` 密钥来自明文头部，无口令交互证据，不做口令弹窗 | — |
| 多仓索引 `lines[]` 嵌套 / `storeHouse` | **未发现真实样本**（采样 34 份 0 命中）；既有解析代码保留但不宣称新增支持 | — |
| 配置级 gzip | **不支持（未发现真实样本）**：传输层压缩由 URLSession 透明解压 | — |
| 纯文本直播列表（`频道,#genre#`） | 维持移除（`lives` 不建模） | `qist/tvbox/master/ITV.txt` |

- **安全基线**：AES 密钥只在内存参与 `CCCrypt`，不写日志、不进错误文案；错误提示只报结构性原因（「缺少 `$#…#$` 密钥段」「密文长度不是 16 的整数倍」），由 `Build25ConfigFormatRegressionTests.testAESFailureMessageNeverLeaksKey` 固化。
- **关键实现口径**：base64 的 `**` 标记必须在**字节层**检索——二进制前导使严格 UTF-8 解码失败后，GB18030 回落会按双字节消耗前导高位字节、吞掉紧随的 ASCII 标记（实测字符串层找不到 `**`），由 `testBase64MarkerDisappearsIfDecodedFirst` 固化。
- build 24 的 15 条回归口径（行注释/块注释/尾逗号/BOM/GBK/错误提示行号片段）全部保留，未推翻既有 `stripJSONNoise` / `analyze` 结构。
