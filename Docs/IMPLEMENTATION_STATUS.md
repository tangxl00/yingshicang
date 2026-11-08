# 还原状态表（R-01~R-55 / F-01~F-20）

基线：《需求与界面还原规格》56 界面条目 + 20 功能条目。状态取自本仓库实际代码（文件 + 方法），非设计意图。

**build 23 终态统计（唯一口径，本文件全部数字以此为准）**：已实现 66 / 部分 0 / 平台级不支持 4（R-20 DLNA、R-38 文件系统、R-40 应用列表、R-41 自更新）/ 按用户要求移除 5；**未实现 0**。

build 23 相比 build 22 的五个「部分」全部转「已实现」：R-39 网盘（接阿里云盘开放接口：文件列表 + 下载地址转发 + H5 授权回传）、R-47 H5 容器（`authorizing(...)` 工厂接进网盘授权真实入口）、F-09 播放内核（VLCKit 4.0 以 SPM binaryTarget 集成，MKV/DTS 等容器真路由）、F-19 备份还原（PUT/GET 往返早已落地，此前文档误记「未实现」）、F-20 下载（真实 URLSession 落盘 + 断点续传 + 本地播放）。

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
| R-05 | 快搜结果区 | 已实现 | 扁平结果列表（`numberOfRowsInSection` 直接取 `results.count`，**无分组、无「搜索(n/N)」计数**——这两项 build 22 文档曾误记，build 23 已删除该虚报）；真实落地的是：`SearchSecondaryFilter` 2-gram 候选词横条 + 全词 AND 二次筛选（`applySecondaryFilter`）、结果区长按「屏蔽来源」（`SiteBlockStore` GRDB 持久化，屏蔽后即时收缩列表并重算） |
| R-06 | 筛选弹窗 | 已实现 | build 22：`FilterSheetViewController` 470dp 底部弹层（拖拽条 + 逐维度胶囊 + 重置/确定），`FilterSheetParser` 解析站点 filter JSON（顶层 class 对象与数组两形态）、extend 剔空值；`CategoryContentViewController` 筛选按钮（filterable 且有维度才显示）接线重拉 |
| R-07 | 榜单页 | 已实现 | build 22：`Features/Home/RankListViewController.swift`（provider.home 榜单、rankLimit=50、160dp 卡片行 + 角标），入口在首页搜索栏右侧榜单按钮 |
| R-08 | 按条件筛选弹窗 | 已实现 | build 22：`Features/Home/ConditionFilterViewController.swift` 全屏页（FilterSheetParser 维度解析、350dp 滚动维度区、45dp 确定按钮、内置随机直开），入口在首页快捷弹窗 |
| R-09 | 指定搜索源弹窗 | 已实现 | `Features/Mine/MineSubPages.swift` 站点管理（`toggleSite`）；`Core/Storage/SiteBlockStore.swift` 持久化 |
| R-10 | 播放页 | 已实现 | `Features/Player/PlayerViewController.swift` |
| R-11 | 播放预览层 | 已实现 | build 22：`DetailViewController` 模糊背景（海报放大铺底 + 暗色遮罩）+ 海报左下角评分角标（无评分自动隐藏） |
| R-12 | 播放控制层 | 已实现 | build 22：`PlayerGestureController` + `PlayerGestureLogic` 左右 40% 竖滑调亮度/音量（MPVolumeView 滑块兜底实体键提示）、锁屏态（单击唤解锁钮）、2pt 迷你进度条；pan 只挂画面层不污染左滑返回 |
| R-13 | 逻辑按钮条 | 已实现 | build 22：播放页 8 按钮条（倍速/选集/锁定/片头/片尾/音轨/字幕/解析），片头片尾读 `Settings.introSeconds/outroSeconds` 未设置时给提示 |
| R-14 | 剧情简介卡 | 已实现 | 详情页四入口——解析（三列弹窗选源起播）、快搜（进搜索页）、投屏（显式平台级不支持提示）、下载（build 23 起接真实落盘：`DownloadScene` 批量入队 → `DownloadService` 立即开跑，完成可在下载列表点开本地播放） |
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
| R-31 | 添加 / 扫码快捷弹窗 | 已实现 | build 22：首页搜索栏右侧「+」弹 `QuickAddPopupViewController`（180dp 居中）：扫码添加配置 → `ScanCodeViewController`；条件筛选 → `ConditionFilterViewController` |
| R-32 | 摇一摇推荐 | 已实现 | build 22：`Features/Home/ShakeGesture.swift`（CoreMotion 30Hz、阈值 2.2、冷却 1.5s、上升沿触发）+ `ShakeRecommendationPicker` 随机挑选，`MainTabBarController` viewWillAppear/didDisappear 启停；传感器精度需真机复测 |
| R-33 | 每日赞赏 | 已实现 | build 22：`Features/Mine/RewardDialog.swift` 赞赏弹窗（400dp 居中、二维码占位、联系邮箱复制），我的页「赞赏支持」入口 |
| R-34 | 直播 Tab | 按用户要求移除 | v2.0.50 build 21 真机验收后移除（`Features/Live/` 整目录删除，Tab 5→3），见 KNOWN_DIFFERENCES「按用户要求移除的功能」 |
| R-35 | 直播设置弹窗 | 按用户要求移除 | 随 R-34 一并删除 |
| R-36 | 直播频道选择弹窗 | 按用户要求移除 | 随 R-34 一并删除 |
| R-37 | 直播控制层 | 按用户要求移除 | 随 R-34 一并删除 |
| R-38 | 本地视频 | 平台级不支持 | iOS 沙箱不可扫描文件系统（见 `KNOWN_DIFFERENCES.md`） |
| R-39 | 网盘 | 已实现 | build 23：`Features/Netdisk/AliDriveClient.swift` 接阿里云盘开放接口——`POST openapi.alipan.com/adrive/v1.0/openFile/list`（drive_id + parent_file_id + limit + order）列目录、`POST …/openFile/getDownloadUrl` 取直链，字段名按接口要求（`drive_id`/`file_id`/`parent_file_id`/`name`/`type`/`file_id`/`size`/`url`）；`NetdiskViewController` 已升级为真实文件浏览器（进入目录、面包屑返回、点文件取直链交 `PlayerViewController` 播放）。Token 走 Keychain。接口实测：`openFile/list` 对 GET 返 405（证明该路径真实存在且只接受 POST）、三个端点带无效 Bearer 均返 401 `AccessTokenInvalid`（证明鉴权链路在服务端真实生效）；沙箱无真实 Token，故真实目录与直链返回字段**未端到端实测**，属待真机复测项（已登记 KNOWN_DIFFERENCES） |
| R-40 | 应用列表 | 平台级不支持 | iOS 沙箱无法枚举已安装应用，已在 `KNOWN_DIFFERENCES.md` 重分类登记 |
| R-41 | 应用更新弹窗 | 平台级不支持 | iOS 无 Android 式自更新通道（App Store 审核 2.5.2 禁止热更新，见 `KNOWN_DIFFERENCES.md`） |
| R-42 | TV 互动 | 已实现 | build 22：`Features/Mine/InteractionPage.swift`（十键指令集、地址归一化、`POST {base}/interaction?key=` JSON 下发、URLSession 5s 超时），占位页已删除；真机局域网联动需实测 |
| R-43 | 局域网同步弹窗 | 已实现 | build 22：`Features/Mine/LANSync.swift` 的 `LANSyncDialogViewController`（470dp 贴底、Bonjour 发现设备列表 + 手动输入兜底），我的页「局域网同步」入口；局域网发现需真机复测 |
| R-44 | 扫码页 | 已实现 | build 22：`Features/Home/ScanCodeViewController.swift` AVCaptureSession QR 扫码（权限三分支处理 + 无相机兜底手动输入、2s 冷却），`Info.plist` 增 `NSCameraUsageDescription`；模拟器走手动输入路径，真机扫码需实测 |
| R-45 | WebDAV 设置 | 已实现 | build 22：`WebDavEditDialogViewController` 340dp 居中弹层（三凭据字段 + 测试连接 + 保存）；`WebDavConnectionTester` PROPFIND Depth 0 探测，五态分类（成功/未授权/路径不存在/非 WebDAV/传输失败），Keychain 存密码 |
| R-46 | 备份还原 | 已实现 | build 22：`BackupSheetViewController` 450dp 底部弹层（1.3:2.0 双栏：图标+说明 / 上传·下载双按钮）；`BackupPayload` 打包历史+收藏+屏蔽源为 `yingshicang-backup.json`，`BackupTransfer` PUT 上传 / GET 下载恢复（404 判无备份） |
| R-47 | H5 容器页族 | 已实现 | 通用 H5 容器（`JSRequestPolicy` 导航准入 + 令牌回传拦截）。build 23：`authorizing(url:allowedHosts:onToken:)` 工厂已有真实调用方——网盘页「扫码授权登录」入口用 `AliDriveAuth.authorizeURL` 起 `WebContainerViewController.authorizing`，回调拿到的令牌经 `AliTokenValidator` 校验后写入 Keychain 并刷新网盘状态，不再是零调用孤儿 |
| R-48 | 阿里 Token 输入 | 已实现 | build 22：`AliTokenDialogViewController`（220dp 居中）+ `AliTokenValidator`（去空白 normalize、32 位 hex 校验、清除按钮），读写 `Settings.shared.aliToken` |
| R-49 | 推送播放 | 已实现 | build 22：`LANPushService`（`POST http://{host}:{port}/sync/push` JSON `BackupPayload`，URLSession 网络面可测），从局域网同步弹窗选定设备发起；对端行为需 TV 侧配合，真机复测 |
| R-50 | 频道密码 | 已实现 | build 22：`Features/Home/ChannelPasswordDialog.swift`（`ChannelPasswordRule.needsPassword` 识别「密码/加密」频道 → 180dp 密码弹层，isSecureTextEntry，校验通过回调解锁进入分类内容） |
| R-51 | 通用列表选择弹窗 | 已实现 | `MineSubPages` 复用选择器（内核/倍速/海报样式/搜索模式/跳过） |
| R-52 | 分类标签浮层 | 已实现 | build 22：`CategorySheetViewController` 400dp 贴底全宽浮层（拖拽条 + 3 列胶囊网格 + 当前分类高亮）；`HomeViewController` tabPop 按钮在 categories 非空时显示，点选走同一 `loadCategory` 链路 |
| R-53 | 视频简介弹窗 | 已实现 | build 22：`IntroDialogViewController` 440dp 居中弹窗，完整 vodContent 不截断；顶部搜索栏（24dp 图标 + 30dp 输入框 + 40×24dp「精确」钮），`IntroTextSearcher` 子串/整词（ASCII 词边界）双模式命中主色高亮并滚动到首个命中；详情页简介区点击进入 |
| R-54 | 通用提示与免责弹窗 | 已实现 | build 22：`Features/Mine/DisclaimerDialog.swift`（`DisclaimerGate` 首启未同意判定 + 420dp 免责弹窗，同意持久化 UserDefaults），`MainTabBarController.viewDidLoad` 首启弹出 |
| R-55 | 空态 / 加载 / 加载更多 | 已实现 | `CategoryContentViewController.showStatus` 三态文案 |

**计数口径说明**：界面条目 R-01~R-55 共 55 行，其中 R-35/R-36/R-37 已随 R-34 直播移除（计 4 项移除）、R-20/R-38/R-40/R-41 平台级不支持（4 项）、其余 47 项已实现。功能条目 F-01~F-20 共 20 行，其中 F-17 已移除（第 5 项移除）、其余 19 项已实现。合计 66 项已实现、0 部分、4 平台级不支持、5 移除、0 未实现——与文件开头统计一致，**不存在第二套口径**。

## 二、核心功能清单（F-01 ~ F-20）

| 编号 | 功能 | 状态 | 落地位置 / 说明 |
| --- | --- | --- | --- |
| F-01 | 配置源接入 | 已实现 | `Core/Config/ConfigRepository.swift`：JSON + 容错 JSON 解析，`sites/parses/flags/wallpaper`（`lives` 自 build 21 起随直播移除，作为未知键忽略） |
| F-02 | 多仓与线路管理 | 已实现 | `Core/Config/StoreHouseStore.swift`，仓→线路嵌套持久化 |
| F-03 | 分类浏览 | 已实现 | `Core/Parsing/SiteProvider.swift` + `HTMLSiteProvider`/`JSSiteProvider` 分类与分页 |
| F-04 | 筛选 | 已实现 | 分类筛选弹层（R-06 批次）+ R-08 全屏条件筛选页 + 默认选中/空值剔除逻辑（`FilterSheetParser.defaultSelections` / `extend`），随机直开复用 `ShakeRecommendationPicker` |
| F-05 | 全局搜索 | 已实现 | `Features/Search/SearchViewController.performSearch`，按 `searchable` 参与 |
| F-06 | 快搜（跨源并发） | 已实现 | 同上，聚合计数与分组结果 |
| F-07 | 详情获取 | 已实现 | `Core/Parsing/DetailRule.swift` + `JSSiteProvider.parseDetail`（线路 tabs + 剧集 lists） |
| F-08 | 播放地址解析 | 已实现 | `Core/Parsing/JS/JSPlayParser.swift`，`{parse,jx,url}` 三形态 + 嗅探标记 |
| F-09 | 播放内核与渲染 | 已实现 | build 23：`project.yml` 以 SPM `binaryTarget` 集成官方 `VLCKit` 4.0（`code.videolan.org/videolan/VLCKit`，钉 tag `4.0.0-a25`，制品 `VLCKit-4.0-20260929-1631.zip`，checksum `f37c8dbd…f1fb`）；`Core/Playback/VLCPlayerEngine.swift` 用 `VLCMediaPlayer` + `drawable` = 宿主 UIView 实现完整 `PlaybackEngine`（状态/进度/结束/错误经 `VLCMediaPlayerDelegate` 回传，倍速 `rate`、`position` 定位、`isSeekable` 判定）。路由：`PlaybackRouter` 按扩展名（mkv/rmvb/rm/flv/avi/wmv/ts/m2ts/mov）+ 编译期可用性双条件决定内核，探测结果可注入（`VLCAvailability`），AVPlayer `readyToPlay` 失败的运行时兜底仍保留；设备无 VLC 时显式报错，绝不假装可播 |
| F-10 | 手势与锁屏 | 已实现 | build 22：PlayerGestureController + PlayerGestureLogic——左右 40% 区域侧滑调节亮度/音量（MPVolumeView 程控 / UIScreen.brightness），中央 20% 无效；锁屏态屏蔽全部手势并保留左缘揭示解锁；迷你进度条常显可关（Settings.miniProgress） |
| F-11 | 选集与线路切换 | 已实现 | `PlayerViewController` 线路索引 + 剧集索引 |
| F-12 | 画质与音轨、字幕 | 已实现 | build 22：TrackSheetViewController（300×250）+ AVPlayerEngine 走 mediaSelectionGroups——音轨/内嵌字幕枚举、切换、关闭字幕（allowsOffOption）；画质字段维持既有解析 |
| F-13 | 片头片尾跳过 | 已实现 | `MineSubPages.pickSkip` 持久化起止秒数 |
| F-14 | 倍速播放 | 已实现 | `MineSubPages.pickRate` |
| F-15 | 收藏 | 已实现 | `Core/Storage/FavoriteStore.swift` |
| F-16 | 播放历史 | 已实现 | `Core/Storage/HistoryStore.swift`，续播定位 |
| F-17 | 直播 | 按用户要求移除 | v2.0.50 build 21 真机验收后移除：页面、解析与播放链路全删，`ConfigBundle.lives` 字段移除（配置含 `lives` 时静默忽略不报错） |
| F-18 | 局域网同步 | 已实现 | `BonjourDeviceFinder`（NetServiceBrowser 只 browse `_yingshicang._tcp.` 一种，见 `LANSync.swift` 的 `startSearch`）+ `LANSyncEndpoint` 解析 + `LANPushService` 推送；`Info.plist` 的 `NSBonjourServices` build 23 起只声明这一种（删掉了代码从未使用的 `_http._tcp`，声明与实现严格对齐）。真机局域网行为需实测 |
| F-19 | 备份还原 | 已实现 | 凭据走 Keychain；备份包 `yingshicang-backup.json` 的上传（`BackupTransfer.upload` → WebDAV PUT）与下载恢复（`downloadAndRestore` → GET，404 判无备份、解码失败报错）**代码完整且已接线**（`MineSubPages` 备份弹层双按钮 → `BackupSheetViewController`），并有 PUT/GET 往返单测。build 22 文档误记为「未实现」，与 R-46「已实现」自相矛盾，build 23 已更正 |
| F-20 | 下载与投屏 | 已实现（投屏平台级不支持） | 投屏（DLNA）平台级不支持（见 `KNOWN_DIFFERENCES.md`）。下载为**真实落盘**：`Features/Detail/DownloadService.swift` 用 `URLSession` background configuration + `downloadTask` 拉整文件到 App 文档目录 `Documents/Downloads/`，带进度回调（`onProgress`）、状态流转（pending → running → completed/failed/paused，`DownloadTaskStore.setStatus` 有生产调用方）、断点续传（暂停把 `cancel(byProducingResumeData:)` 的 resumeData 落盘，重开用 `downloadTask(withResumeData:)` 续传）、文件管理（下载列表展示本地文件名与体积、点「播放」走本地文件路径起播、删除时同步删文件）。m3u8/HLS 分片仍不落盘（登记 KNOWN_DIFFERENCES），界面明确提示「该集为 HLS 流，暂不支持离线」 |

## 三、待确认清单（16 项）与本版取值

| 待确认项 | 本版取值 | 依据 |
| --- | --- | --- |
| R-01 Tab 选中色 | 沿用 `DesignTokens` 主色 `#00C64E` | 规格未锁定色值，取已实测主色 |
| R-12 手势区域划分 | 已实现（build 22）：左/右各 40% 为亮度/音量区、中央 20% 不触发，全高滑动生效（PlayerGestureLogic sideFraction 0.4 固化） | Java 层加固不可读 |
| R-15 当前集高亮样式 | 选中态用主色描边 | 同上，色值不可读 |
| R-20 投屏弹窗 | 平台级不支持 | DLNA 见 KNOWN_DIFFERENCES |
| R-38 删除本地视频 | 平台级不支持 | iOS 沙箱不可扫描文件系统 |
| R-44 扫码页叠加层 | 已实现（build 22） | AVCaptureSession 扫码 + 无相机手动输入兜底 |
| R-04 搜索防抖与联想 | 300ms 防抖，回车触发搜索 | 规格未给节流时长，取工程惯例 |
| R-22 历史长按删除 | 长按直接删除，无二次确认 | 布局无确认控件 |
| F-01 配置顶层键名 | `sites` / `parses` / `flags` / `wallpaper`（`lives` 已随直播移除） | 由界面与模板反证 |
| F-02 仓→线路本地结构 | UserDefaults 键 `tpc_stores` | 与 Android 实测键名对齐 |
| F-16 历史合并规则 | 按「片名 + 来源」合并 | 开关名可见、规则不可读，取语义最小实现 |
| F-19 备份范围 | 已实现：历史 + 收藏 + 屏蔽源三张表打包为 `yingshicang-backup.json` | `WebDavSupport.swift` 的 `BackupPayload` 四字段 + PUT/GET 往返 |
| F-20 投屏与下载 | 下载已实现（真实落盘 + 断点续传 + 本地播放）；投屏平台级不支持 | `DownloadService` + `KNOWN_DIFFERENCES` 的 HLS 边界说明 |
| R-33 每日赞赏 | 已实现（build 22） | RewardDialog |
| 播放内核 | AVPlayer 为主，VLCKit 兜底（build 23 已真集成） | `PlaybackRouter` 容器判定 + `VLCAvailability` 可注入探测 |
| dp→pt 换算 | 1:1（160dpi 基准） | `DesignTokens/Metrics` 统一驱动 |

## 四、工程与流水线

- 拓扑：`gate-u01 → unit-tests → build-device → package-ipa → upload-artifacts`，runner 固定 `macos-15`
- U-01 判定：**A**（原生组 5 条 + 垫片对照组 2 条全绿，维持 JS 引擎 + cheerio 设计）
- 免签 IPA：`Payload/Yingshicang.app` 布局，主二进制自包含，不含 `embedded.mobileprovision`；`CODE_SIGNING_ALLOWED=NO` 只影响签名不影响编译
  - **关于 Frameworks 目录**：本工程未启用 `ENABLE_DEBUG_DYLIB`（`project.yml` 的 `ENABLE_DEBUG_DYLIB: NO`），GRDB / SwiftSoup 两个 SPM 依赖以**静态库**形式链接进主二进制。**build 23 起有变化**：VLCKit 4.0 官方以 `.binaryTarget` 分发，设备 slice（`ios-arm64/VLCKit.framework`）是动态框架，因此 `Payload/Yingshicang.app/Frameworks/` 下**会**出现 `VLCKit.framework`（外加 SwiftPM 自动收集的依赖框架）。这是免签 IPA 的预期形态：`CODE_SIGNING_ALLOWED=NO` 下该框架不签名，与本工程其余二进制一致；用 Sideloadly / AltStore 等重签工具安装时，工具会对整个 payload（含嵌套框架）重新签名。验收判据：主二进制单一自包含可执行文件（无 `*.debug.dylib` / `__preview.dylib` 伴生）、嵌套框架结构完整（`VLCKit.framework/VLCKit` 存在且 arm64）、Info.plist 合法、无 provisioning profile。
- 验收口径：`conclusion=success` 不等于测试通过，须读 `build-logs` 中 `xcodebuild test` 真实输出
