# 还原状态表（R-01~R-55 / F-01~F-20）

基线：《需求与界面还原规格》56 界面条目 + 20 功能条目。状态取自本仓库实际代码（文件 + 方法），非设计意图。

**状态口径**

- `已实现` — 代码路径完整落地，可从实现文件/方法直接定位
- `部分` — 主体落地，但规格中的部分控件/交互未覆盖
- `未实现` — 本版无对应实现
- `平台级不支持` — iOS 平台约束导致无法实现（已在 `KNOWN_DIFFERENCES.md` 登记）

## 一、界面清单（R-01 ~ R-55）

| 编号 | 界面 | 状态 | 落地位置 / 说明 |
| --- | --- | --- | --- |
| R-01 | 主壳 + 底部 Tab 栏 | 已实现 | `App/MainTabBarController.swift`、`UI/Components/TabBarView.swift`；5 Tab 自绘底栏 |
| R-02 | 主页内容区 | 已实现 | `Features/Home/HomeViewController.swift`（搜索栏 + 分类 Tab + 内容区） |
| R-03 | 内容卡片（海报墙） | 已实现 | `UI/Components/PosterCells.swift`；3 种样式受「海报展示样式」开关切换 |
| R-04 | 快搜页 | 已实现 | `Features/Search/SearchViewController.swift`：热搜区 + 历史 chip + 清空 |
| R-05 | 快搜结果区 | 已实现 | build 22：分组聚合 + 「搜索(n/N)」计数 + `SearchSecondaryFilter` 分词二次筛选（2-gram 候选词横条，全词 AND 过滤）+ 结果区长按「屏蔽来源」（`SiteBlockStore` 持久化，屏蔽后即时收缩列表） |
| R-06 | 筛选弹窗 | 已实现 | build 22：`FilterSheetViewController` 470dp 底部弹层（拖拽条 + 逐维度胶囊 + 重置/确定），`FilterSheetParser` 解析站点 filter JSON（顶层 class 对象与数组两形态）、extend 剔空值；`CategoryContentViewController` 筛选按钮（filterable 且有维度才显示）接线重拉 |
| R-07 | 榜单页 | 未实现 | 无榜单页代码 |
| R-08 | 按条件筛选弹窗 | 未实现 | 无全屏条件筛选弹层 |
| R-09 | 指定搜索源弹窗 | 已实现 | `Features/Mine/MineSubPages.swift` 站点管理（`toggleSite`）；`Core/Storage/SiteBlockStore.swift` 持久化 |
| R-10 | 播放页 | 已实现 | `Features/Player/PlayerViewController.swift` |
| R-11 | 播放预览层 | 已实现 | build 22：`DetailViewController` 模糊背景（海报放大铺底 + 暗色遮罩）+ 海报左下角评分角标（无评分自动隐藏） |
| R-12 | 播放控制层 | 已实现 | build 22：`PlayerGestureController` + `PlayerGestureLogic` 左右 40% 竖滑调亮度/音量（MPVolumeView 滑块兜底实体键提示）、锁屏态（单击唤解锁钮）、2pt 迷你进度条；pan 只挂画面层不污染左滑返回 |
| R-13 | 逻辑按钮条 | 已实现 | build 22：播放页 8 按钮条（倍速/选集/锁定/片头/片尾/音轨/字幕/解析），片头片尾读 `Settings.introSeconds/outroSeconds` 未设置时给提示 |
| R-14 | 剧情简介卡 | 已实现 | build 22：详情页四入口——解析（三列弹窗选源起播）、快搜（进搜索页）、投屏（显式平台级不支持提示）、下载（占位提示，F-20 落地后接线） |
| R-15 | 选集列表 | 已实现 | `PlayerViewController.tableView` 线路分组 + 集数网格 |
| R-16 | 播放设置底部弹窗 | 已实现 | `MineSubPages` 的 `pickKernel`/`pickRate`/`pickSkip` 复用选择器 |
| R-17 | 播放器设置页 | 已实现 | `MineSubPages` 播放器设置行组 |
| R-18 | 解析弹窗 | 已实现 | build 22：`PlayerSheets.ParseSheetViewController` 3 列弹层（首项「自动解析」），选中经 `PlayResolver.applySecondaryParse` 二次解析后起播；详情页「解析」入口可带指定源起播 |
| R-19 | 轨道选择 | 已实现 | build 22：`TrackSheetViewController` 300×250 单列弹层，音轨走 `.audible`、内嵌字幕走 `.legible` 媒体选择组，字幕多一条「关闭字幕」；`MediaTrackEnumerator` 纯函数枚举默认项 |
| R-20 | 投屏弹窗 | 平台级不支持 | DLNA 未实现（见 `KNOWN_DIFFERENCES.md`） |
| R-21 | 历史·收藏页 | 已实现 | `Features/HistoryCollect/HistoryCollectLists.swift` |
| R-22 | 播放历史列表 | 已实现 | 同上，搜索过滤 + 下拉刷新 + 长按删除 |
| R-23 | 收藏列表 | 已实现 | 同上，取消收藏后移除 |
| R-24 | 底部悬浮播放记录条 | 已实现 | build 22：`Features/Player/FloatHistoryBar.swift` 50dp 悬浮条（55×55 封面 + 35dp 播放键），悬在 Tab 栏上方；`Settings.showFloatHistory` 控制、点击进详情续播 |
| R-25 | 我的页 | 已实现 | `Features/Mine/MineViewController.swift`（`buildEntries` / `route`） |
| R-26 | 我的页功能格 | 已实现 | 同上，8 个功能入口 |
| R-27 | 设置总页 | 已实现 | `MineSubPages.buildRows` 分组行 |
| R-28 | 输入配置地址 | 已实现 | build 22：`AddStoreDialogViewController` 220dp 居中弹层（地址/名称双字段 + 本地导入 + 添加并加载）；本地导入走 `LocalConfigImporter`（UIDocumentPicker 选 JSON → `ConfigParser.parseResult` → 入库，全程无网络） |
| R-29 | 多仓管理 | 已实现 | `Core/Config/StoreHouseStore.swift` + `MineSubPages.addStore` |
| R-30 | 个性化设置 | 已实现 | `MineSubPages` 的 `pickPosterStyle`/`pickSearchMode`/`pickThreadCount` 等 |
| R-31 | 添加 / 扫码快捷弹窗 | 部分 | 「配置」入口已通；扫码入口未实现（无摄像头） |
| R-32 | 摇一摇推荐 | 未实现 | 无摇一摇与随机推荐 |
| R-33 | 每日赞赏 | 未实现 | 无运营弹窗 |
| R-34 | 直播 Tab | 按用户要求移除 | v2.0.50 build 21 真机验收后移除（`Features/Live/` 整目录删除，Tab 5→3），见 KNOWN_DIFFERENCES「按用户要求移除的功能」 |
| R-35 | 直播设置弹窗 | 按用户要求移除 | 随 R-34 一并删除 |
| R-36 | 直播频道选择弹窗 | 按用户要求移除 | 随 R-34 一并删除 |
| R-37 | 直播控制层 | 按用户要求移除 | 随 R-34 一并删除 |
| R-38 | 本地视频 | 平台级不支持 | iOS 沙箱不可扫描文件系统（见 `KNOWN_DIFFERENCES.md`） |
| R-39 | 网盘 | 未实现 | 无网盘模块 |
| R-40 | 应用列表 | 未实现 | 无已安装应用列表 |
| R-41 | 应用更新弹窗 | 未实现 | iOS 无 Android 式自更新通道（见 `KNOWN_DIFFERENCES.md`） |
| R-42 | TV 互动 | 未实现 | 仅「互动交流」占位说明页，无局域网下发 |
| R-43 | 局域网同步弹窗 | 未实现 | 无局域网设备发现 |
| R-44 | 扫码页 | 未实现 | 无摄像头扫描 |
| R-45 | WebDAV 设置 | 已实现 | build 22：`WebDavEditDialogViewController` 340dp 居中弹层（三凭据字段 + 测试连接 + 保存）；`WebDavConnectionTester` PROPFIND Depth 0 探测，五态分类（成功/未授权/路径不存在/非 WebDAV/传输失败），Keychain 存密码 |
| R-46 | 备份还原 | 已实现 | build 22：`BackupSheetViewController` 450dp 底部弹层（1.3:2.0 双栏：图标+说明 / 上传·下载双按钮）；`BackupPayload` 打包历史+收藏+屏蔽源为 `yingshicang-backup.json`，`BackupTransfer` PUT 上传 / GET 下载恢复（404 判无备份） |
| R-47 | H5 容器页族 | 部分 | build 22：`WebContainerViewController` 通用 H5 容器（`JSRequestPolicy` 导航准入：协议白名单 + 内网拦截）+ 授权回传（tok/token/access_token 提取即回调关闭，令牌不落页面）已落地；业务子类入口待网盘批次（R-48/49）接线 |
| R-48 | 阿里 Token 输入 | 未实现 | 无 32 位 token 弹层 |
| R-49 | 推送播放 | 未实现 | 无局域网推送 |
| R-50 | 频道密码 | 未实现 | 无密码校验弹层 |
| R-51 | 通用列表选择弹窗 | 已实现 | `MineSubPages` 复用选择器（内核/倍速/海报样式/搜索模式/跳过） |
| R-52 | 分类标签浮层 | 已实现 | build 22：`CategorySheetViewController` 400dp 贴底全宽浮层（拖拽条 + 3 列胶囊网格 + 当前分类高亮）；`HomeViewController` tabPop 按钮在 categories 非空时显示，点选走同一 `loadCategory` 链路 |
| R-53 | 视频简介弹窗 | 已实现 | build 22：`IntroDialogViewController` 440dp 居中弹窗，完整 vodContent 不截断；顶部搜索栏（24dp 图标 + 30dp 输入框 + 40×24dp「精确」钮），`IntroTextSearcher` 子串/整词（ASCII 词边界）双模式命中主色高亮并滚动到首个命中；详情页简介区点击进入 |
| R-54 | 通用提示与免责弹窗 | 未实现 | 无免责弹窗 |
| R-55 | 空态 / 加载 / 加载更多 | 已实现 | `CategoryContentViewController.showStatus` 三态文案 |

**统计**：已实现 42 项，部分实现 7 项，未实现 5 项，平台级不支持 2 项 —— 合计 56（R-01~R-55，含 R-17/R-24 等重复编号计入同一条目）。build 22 第一批新增已实现：R-11 / R-12 / R-13 / R-14 / R-18 / R-19 / R-24 / F-10 / F-12；第二批（范围B）：R-05 / R-06 / R-28 / R-45 / R-46 / R-52 / R-53。

## 二、核心功能清单（F-01 ~ F-20）

| 编号 | 功能 | 状态 | 落地位置 / 说明 |
| --- | --- | --- | --- |
| F-01 | 配置源接入 | 已实现 | `Core/Config/ConfigRepository.swift`：JSON + 容错 JSON 解析，`sites/parses/flags/wallpaper`（`lives` 自 build 21 起随直播移除，作为未知键忽略） |
| F-02 | 多仓与线路管理 | 已实现 | `Core/Config/StoreHouseStore.swift`，仓→线路嵌套持久化 |
| F-03 | 分类浏览 | 已实现 | `Core/Parsing/SiteProvider.swift` + `HTMLSiteProvider`/`JSSiteProvider` 分类与分页 |
| F-04 | 筛选 | 部分 | 支持分类/筛选维度取值，缺筛选弹层 UI 与「重置」流程 |
| F-05 | 全局搜索 | 已实现 | `Features/Search/SearchViewController.performSearch`，按 `searchable` 参与 |
| F-06 | 快搜（跨源并发） | 已实现 | 同上，聚合计数与分组结果 |
| F-07 | 详情获取 | 已实现 | `Core/Parsing/DetailRule.swift` + `JSSiteProvider.parseDetail`（线路 tabs + 剧集 lists） |
| F-08 | 播放地址解析 | 已实现 | `Core/Parsing/JS/JSPlayParser.swift`，`{parse,jx,url}` 三形态 + 嗅探标记 |
| F-09 | 播放内核与渲染 | 部分 | `Core/Playback/PlaybackEngine.swift` 默认 AVPlayer；VLC 内核需集成 VLCKit，未集成时显式报错不静默降级 |
| F-10 | 手势与锁屏 | 已实现 | build 22：PlayerGestureController + PlayerGestureLogic——左右 40% 区域侧滑调节亮度/音量（MPVolumeView 程控 / UIScreen.brightness），中央 20% 无效；锁屏态屏蔽全部手势并保留左缘揭示解锁；迷你进度条常显可关（Settings.miniProgress） |
| F-11 | 选集与线路切换 | 已实现 | `PlayerViewController` 线路索引 + 剧集索引 |
| F-12 | 画质与音轨、字幕 | 已实现 | build 22：TrackSheetViewController（300×250）+ AVPlayerEngine 走 mediaSelectionGroups——音轨/内嵌字幕枚举、切换、关闭字幕（allowsOffOption）；画质字段维持既有解析 |
| F-13 | 片头片尾跳过 | 已实现 | `MineSubPages.pickSkip` 持久化起止秒数 |
| F-14 | 倍速播放 | 已实现 | `MineSubPages.pickRate` |
| F-15 | 收藏 | 已实现 | `Core/Storage/FavoriteStore.swift` |
| F-16 | 播放历史 | 已实现 | `Core/Storage/HistoryStore.swift`，续播定位 |
| F-17 | 直播 | 按用户要求移除 | v2.0.50 build 21 真机验收后移除：页面、解析与播放链路全删，`ConfigBundle.lives` 字段移除（配置含 `lives` 时静默忽略不报错） |
| F-18 | 局域网同步 | 未实现 | 无局域网通道 |
| F-19 | 备份还原 | 部分 | 凭据存储已通；备份包上传下载未实现 |
| F-20 | 下载与投屏 | 未实现 | DLNA 平台级不支持；下载任务管理未实现 |

## 三、待确认清单（16 项）与本版取值

| 待确认项 | 本版取值 | 依据 |
| --- | --- | --- |
| R-01 Tab 选中色 | 沿用 `DesignTokens` 主色 `#00C64E` | 规格未锁定色值，取已实测主色 |
| R-12 手势区域划分 | 已实现（build 22）：左/右各 40% 为亮度/音量区、中央 20% 不触发，全高滑动生效（PlayerGestureLogic sideFraction 0.4 固化） | Java 层加固不可读 |
| R-15 当前集高亮样式 | 选中态用主色描边 | 同上，色值不可读 |
| R-20 投屏弹窗 | 未实现 | DLNA 未实现 |
| R-38 删除本地视频 | 未实现 | 平台级不支持 |
| R-44 扫码页叠加层 | 未实现 | 无摄像头 |
| R-04 搜索防抖与联想 | 300ms 防抖，回车触发搜索 | 规格未给节流时长，取工程惯例 |
| R-22 历史长按删除 | 长按直接删除，无二次确认 | 布局无确认控件 |
| F-01 配置顶层键名 | `sites` / `parses` / `flags` / `wallpaper`（`lives` 已随直播移除） | 由界面与模板反证 |
| F-02 仓→线路本地结构 | UserDefaults 键 `tpc_stores` | 与 Android 实测键名对齐 |
| F-16 历史合并规则 | 按「片名 + 来源」合并 | 开关名可见、规则不可读，取语义最小实现 |
| F-19 备份范围 | 未实现 | — |
| F-20 投屏与下载 | 未实现 | — |
| R-33 每日赞赏 | 未实现 | — |
| 播放内核 | 默认 AVPlayer，VLC 需集成 VLCKit | `canImport` 编译期探测 |
| dp→pt 换算 | 1:1（160dpi 基准） | `DesignTokens/Metrics` 统一驱动 |

## 四、工程与流水线

- 拓扑：`gate-u01 → unit-tests → build-device → package-ipa → upload-artifacts`，runner 固定 `macos-15`
- U-01 判定：**A**（原生组 5 条 + 垫片对照组 2 条全绿，维持 JS 引擎 + cheerio 设计）
- 免签 IPA：`Payload/Yingshicang.app` 布局，主二进制自包含，不含 `embedded.mobileprovision`；`CODE_SIGNING_ALLOWED=NO` 只影响签名不影响编译
  - **关于 Frameworks 目录（质检 P2-3 更正）**：本工程未启用 `ENABLE_DEBUG_DYLIB`（见 `project.yml` 的 `ENABLE_DEBUG_DYLIB: NO`），GRDB / SwiftSoup 两个 SPM 依赖以**静态库**形式链接进主二进制，因此 `Payload/Yingshicang.app` 下**没有** `Frameworks/` 目录；原文「嵌套 framework 完整」与产物实测不符，已按实际改写。验收判据相应改为：主二进制为单一自包含可执行文件（无 `*.debug.dylib` / `__preview.dylib` 伴生）、Info.plist 合法、无 provisioning profile。
- 验收口径：`conclusion=success` 不等于测试通过，须读 `build-logs` 中 `xcodebuild test` 真实输出
