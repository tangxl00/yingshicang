# 已知平台差异与设计决策

记录 iOS 重写相对 Android 2.0.50 原版的已知差异、降级口径与默认取值。U-01 判定结果以 CI 首跑 build-logs 为准回填。

## U-01 前置门判定（cheerio on JavaScriptCore）

- **探针位置**：`U01Gate/Tests/U01GateTests/U01CheerioProbeTests.swift`，跑 macOS（非模拟器）
- **五条断言**：C-1 无异常装载 / C-2 可构造 DOM / C-3 选择器（`:eq`、属性选择器）命中 / C-4 `$.html(node)` 返回字符串 / C-5 真实 `pdfh` 链式调用含 `:eq`、属性提取与 baseUrl 拼接
- **垫片对照组**：仅注入最小 Node 垫片（`global` / `process` / `Buffer` 的类型与编码），不补任何 DOM 能力
- **判定**（待 CI 首跑回填）：
  - [ ] **A** — 两组全绿，维持 JavaScriptCore 原设计
  - [ ] **C** — 原生组失败、垫片组全绿，注入最小垫片重跑
  - [ ] **B** — 两组均失败，降级为宿主 Swift 实现 `pdfh/pdfa/pd`（`Core/Parsing/` 已有备胎实现）

**首跑结果**：待回填（见 Actions `gate-u01` job 与 `build-logs-gate-u01` artifact）

## 平台级不支持

| 差异 | 说明 | 用户可见行为 |
| --- | --- | --- |
| jar 型站点 | iOS 无 JVM，无法运行 Java 爬虫扩展 | 站点列表标注「jar·iOS 不支持」，进入站点显式提示，不静默失败 |
| VLC 播放内核 | MobileVLCKit 无官方 SPM 分发，采用 `canImport` 编译期探测 | 未集成时选择 VLC 内核会明确报错「当前构建未集成 VLC 内核」，不静默降级 |
| 本地视频导入 | iOS 沙箱限制，无法像 Android 一样扫描文件系统 | 「本地数据」页说明受限 |
| 应用内自更新 | App Store / 企业签分发模型下无 Android 式自更新通道 | 「检查更新」页说明 iOS 无自更新通道 |
| DLNA 投屏 / P2P | 未在本版实现 | 不展示对应入口 |
| 互动交流 | 未接入 H5 互动页 | 占位说明页 |

## 默认取值（对齐 Android 实测）

- 主色 `main = #00C64E`，主背景 `mainBg = #001A37`（ARGB 实测自 APK resources.arsc）
- 持久化键名：`tpc_stores` / `tpc_current_line` / `tpc_settings.*` / `tpc_search_history`（UserDefaults；数据库表 favorite / history / lanDevice / blockedSite 对齐 Room）
- 站点 type 路由：0=HTML 解析、1=JSON API、3=JS 爬虫；`csp_` 前缀按 API 处理；jar → Unsupported
- 搜索参与条件：`searchable > 0` 且非 jar 且未被用户屏蔽；聚合线程数取 `searchThreadCount`（上限 8）
- 直播源文本格式 `频道名$地址$备用`，取第一条线路；GB18030 / Big5 编码兜底
- dp→pt 按 1:1 换算（160dpi 基准），全部经 `DesignTokens/Metrics` 统一驱动
