# Yingshicang (影视仓) — iOS 原生重写

影视仓 2.0.50（Android 版）的 iOS 原生实现（Swift / UIKit）。目标是一比一还原原版界面与功能：配置驱动的多源影视聚合（type 0 HTML / type 1 JSON API / type 3 JS 爬虫）、多线路播放、直播源、收藏与观看历史、集合搜索等。

> **本项目仅供学习与技术研究。** 所有影视内容由用户自行配置的第三方数据源提供，本项目不内置、不分发任何内容资源；请遵守当地法律法规使用。

## 工程结构

```
project.yml                 # xcodegen 工程描述（唯一事实源，*.xcodeproj 不入库）
Config/Info.plist           # ATS 全开、权限描述、后台音频
Yingshicang/
  App/                      # AppDelegate、TabBar、首页容器
  DesignTokens/             # Colors / Metrics / Corner（dp→pt 1:1，取自 APK resources.arsc 实测值）
  Core/
    Networking/             # HTTPClient（同步语义 req + GB18030/Big5 解码兜底）
    Parsing/                # HTMLRule / HTMLSelector（SwiftSoup 宿主实现 pdfh/pdfa/pd）
    JS/                     # JSEngine(JavaScriptCore) + JSBridge + drpy JS 站点适配
    Config/                 # 配置解析（宽容 JSON、多仓、FlexKey）
    Storage/                # GRDB（收藏/历史/屏蔽站点/线路仓库）
    Playback/               # AVPlayer 主内核 + VLC 编译期探测兜底
  Features/                 # Home/Search/Detail/Player/Live/ShortVideo/History/Mine
  Resources/Rules/          # 从 APK assets 提取的 JS 规则运行时（cheerio/drpy 等）
U01Gate/                    # U-01 前置门：cheerio 在 macOS JavaScriptCore 上的探针测试包
Tests/                      # 主工程单测（解析层 / 配置层 / 直播源 / 编码）
.github/workflows/ios.yml   # CI：gate-u01 → unit-tests → build-device → package-ipa → upload-artifacts
```

## 本地构建

```bash
brew install xcodegen        # 若未安装
xcodegen generate
open Yingshicang.xcodeproj   # 选模拟器直接 Run
```

依赖（Swift Package）：GRDB ≥ 7.12.0、SwiftSoup ≥ 2.14.3。

## CI 出包（GitHub Actions）

推送 `main` 或手动触发 `iOS CI` workflow，流水线：

1. **gate-u01** — `U01Gate` 包在 macOS 上跑 `U01CheerioProbeTests`（cheerio.bundle.js 装载探针，判定 A/B/C 分支，见 `KNOWN_DIFFERENCES.md`）
2. **unit-tests** — 模拟器上 `xcodebuild test`，真实输出落 build-logs
3. **build-device** — `generic/platform=iOS` 免签 Release 构建
4. **package-ipa** — 组装 `Payload/*.app` 免签 IPA（结构完整、无 `embedded.mobileprovision`，可被重签工具处理）
5. **upload-artifacts** — 汇总 IPA + 全部 build-logs 为 `yingshicang-release-bundle`

Runner 固定 `macos-15`（不使用 `-latest`）。

## 免签 IPA 安装说明

CI 产出的 IPA **未签名**，无法直接安装，需自签后使用：

- **爱思助手**（Windows/macOS）：自签名 + 安装，需 Apple ID
- **AltStore / Sideloadly**：7 天周期自签
- **TrollStore**（符合条件的系统版本）：免签安装

签名团队证书不限；应用不含 entitlements 依赖越狱的能力。

## 平台差异

jar 型站点（Java 爬虫扩展）在 iOS 上无 JVM 运行环境，属平台级不支持，应用内会显式标注；VLC 内核为编译期探测集成，未集成时明确报错、不静默降级。完整清单见 `KNOWN_DIFFERENCES.md`。
