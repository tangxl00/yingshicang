import UIKit

/// 设计令牌：全部数值来自 APK 资源层（res/values/colors.xml、dimens、布局文件），
/// 不来自代码推断——APK Java 层被 360 加固，界面事实以布局与资源表为准。
///
/// dp→pt 换算：Android 的 dp 与 iOS 的 pt 都是「密度无关逻辑单位」，
/// 基准密度 160dpi 时 1dp = 1px = 1pt，故本工程 1dp 直接取 1pt，
/// 不做额外缩放，以保证与文档给出的 dp 值逐项对齐（验收口径要求尺寸一致）。
enum DesignTokens {

    /// 1dp = 1pt 的显式换算入口。所有布局尺寸都必须经过本函数，
    /// 便于未来若需按机型缩放只改这一处。
    @inline(__always)
    static func dp(_ value: CGFloat) -> CGFloat { value }

    /// Android sp 同样按 1:1 落到 pt（仅在系统字号放大时才缩放，本工程不跟随动态字体）。
    @inline(__always)
    static func sp(_ value: CGFloat) -> CGFloat { value }

    /// 从 res/values/colors.xml 提取的实际色值（ARGB → UIColor）。
    enum Colors {
        /// main_bg_color #FF001A37
        static let mainBg = UIColor(hex: 0xFF001A37)
        /// main_color #FF00C64E（主色/强调色）
        static let main = UIColor(hex: 0xFF00C64E)
        /// main_color_light #FF9DE3AA
        static let mainLight = UIColor(hex: 0xFF9DE3AA)
        /// main_bg_color_44 #8F001A37（约 56% 不透明）
        static let mainBg44 = UIColor(hex: 0x8F001A37)
        /// main_dialog_sheet_color #FF233A52
        static let sheet = UIColor(hex: 0xFF233A52)
        /// main_dialog_sheet_color_44 #8F233A52
        static let sheet44 = UIColor(hex: 0x8F233A52)
        /// main_dialog_color #33FFFFFF（白色 20%，弹窗按钮底）
        static let dialog = UIColor(hex: 0x33FFFFFF)
        /// main_confirm_color #FF081B30
        static let confirm = UIColor(hex: 0xFF081B30)
        /// main_input_bg #590F1A26
        static let inputBg = UIColor(hex: 0x590F1A26)
        /// color_FF0057 / color_FF5F00 两个警示/角标橙红
        static let accentRed = UIColor(hex: 0xFFFF0057)
        static let accentOrange = UIColor(hex: 0xFFFF5F00)
        /// black_color_44 #8F000000
        static let black44 = UIColor(hex: 0x8F000000)
        /// black_color_60 #66000000
        static let black60 = UIColor(hex: 0x66000000)
        /// black_color_94 #0F000000（黑 6%）
        static let black94 = UIColor(hex: 0x0F000000)
        /// white_color_44 #8FFFFFFF
        static let white44 = UIColor(hex: 0x8FFFFFFF)
        /// white_color_94 #0FFFFFFF（白 6%）
        static let white94 = UIColor(hex: 0x0FFFFFFF)
        /// text_color #FF999999
        static let text = UIColor(hex: 0xFF999999)
        /// gray_9c #FF9C9C9C
        static let gray = UIColor(hex: 0xFF9C9C9C)
        /// blur_cover_color #C4022C4D
        static let blurCover = UIColor(hex: 0xC4022C4D)
        /// color_32364E / 353744 / 3D3D3D 三个中性灰
        static let neutral32364E = UIColor(hex: 0xFF32364E)
        static let neutral353744 = UIColor(hex: 0xFF353744)
        static let neutral3D3D3D = UIColor(hex: 0xFF3D3D3D)
        /// 通用白 94%（白 6% 叠加）用于列表项底色
        static let cardWhite = UIColor(white: 1.0, alpha: 0.06)

        static let separator = UIColor(white: 1.0, alpha: 0.08)
    }

    /// 逐界面的固定尺寸（均来自布局 XML 直接读取，单位已换算为 pt）。
    enum Metrics {
        /// R-01 底部 Tab 栏：include 高 55dp，内部 paddingTop 5dp，文字 12sp
        static let tabBarHeight: CGFloat = 55
        static let tabBarPaddingTop: CGFloat = 5
        static let tabBarFont: CGFloat = 12

        /// R-02 主页内容区：paddingTop 30dp，TabLayout 高 25dp，tabPop 24dp，ViewPager marginTop 5dp
        static let homePaddingTop: CGFloat = 30
        static let homeTabHeight: CGFloat = 25
        static let homeTabPopupSize: CGFloat = 24
        static let homePagerMarginTop: CGFloat = 5
        static let actionBarHorizontalPadding: CGFloat = 14

        /// R-03 海报卡：比例 220:280，角标 12sp 圆角 4dp，备注 11sp 圆角 4dp，名称 13sp 4 行
        static let posterRatio: CGFloat = 220.0 / 280.0
        static let cardFlagFont: CGFloat = 12
        static let cardNoteFont: CGFloat = 11
        static let cardNameFont: CGFloat = 13
        static let cardCorner: CGFloat = 4
        /// 列表项 60×60 缩略图 + 名称 14sp 3 行
        static let listThumb: CGFloat = 60
        static let listNameFont: CGFloat = 14
        /// 区块项高 200dp 圆角 16dp，标题 16sp，「更多」12sp，横滑 marginTop 10dp
        static let blockHeight: CGFloat = 200
        static let blockCorner: CGFloat = 16
        static let blockTitleFont: CGFloat = 16
        static let blockMoreFont: CGFloat = 12
        static let blockListMarginTop: CGFloat = 10

        /// R-04 快搜页
        static let hotSearchTitleFont: CGFloat = 16
        static let hotSearchCorner: CGFloat = 12
        static let hotSearchContainerPaddingTop: CGFloat = 10
        static let historyClearFont: CGFloat = 14
        static let historyMarginTop: CGFloat = 8
        static let searchResultTopInset: CGFloat = 40

        /// R-05 结果区：标题 120×33dp / 14sp
        static let resultTitleWidth: CGFloat = 120
        static let resultTitleHeight: CGFloat = 33
        static let resultTitleFont: CGFloat = 14

        /// R-06 筛选弹窗：BlurView 与内容高 470dp，paddingTop 15dp，拖拽条 40×4dp 圆角 2dp，标题 18sp，「重置」16sp
        static let filterSheetHeight: CGFloat = 470
        static let sheetContentPaddingTop: CGFloat = 15
        static let dragBarWidth: CGFloat = 40
        static let dragBarHeight: CGFloat = 4
        static let dragBarCorner: CGFloat = 2
        static let sheetTitleFont: CGFloat = 18
        static let sheetActionFont: CGFloat = 16
        static let dragBarTopMargin: CGFloat = 10

        /// R-07 榜单卡：高 160dp，封面高 140dp 比例 448:672，角标 9sp，标题 15sp，元信息 10sp，描述 5 行
        static let rankCardHeight: CGFloat = 160
        static let rankCoverHeight: CGFloat = 140
        static let rankCoverRatio: CGFloat = 448.0 / 672.0
        static let rankBadgeFont: CGFloat = 9
        static let rankTitleFont: CGFloat = 15
        static let rankMetaFont: CGFloat = 10
        static let rankPaddingTop: CGFloat = 10

        /// R-08 条件筛选：标题 16sp marginTop 16，列表高 350dp，确定按钮高 45dp 圆角 8dp
        static let randomFilterListHeight: CGFloat = 350
        static let confirmButtonHeight: CGFloat = 45
        static let confirmButtonCorner: CGFloat = 8

        /// R-09 指定搜索源：圆角 14dp，标题 15sp，搜索框高 40dp 12sp，按钮高 40dp 圆角 5dp，列表高 400dp，项高 40dp 圆角 4dp，开关 40×20dp，14sp
        static let siteBlockCorner: CGFloat = 14
        static let siteBlockTitleFont: CGFloat = 15
        static let siteSearchHeight: CGFloat = 40
        static let siteSearchFont: CGFloat = 12
        static let siteButtonHeight: CGFloat = 40
        static let siteButtonCorner: CGFloat = 5
        static let siteListHeight: CGFloat = 400
        static let siteItemHeight: CGFloat = 40
        static let siteSwitchWidth: CGFloat = 40
        static let siteSwitchHeight: CGFloat = 20
        static let siteItemFont: CGFloat = 14

        /// R-10 播放页：顶栏 37dp，视频 16:9，介绍 marginTop 10dp，「选集」Tab 高 23dp，ViewPager marginTop 10dp
        static let playTopBarHeight: CGFloat = 37
        static let playIntroMarginTop: CGFloat = 10
        static let playSeriesTabHeight: CGFloat = 23
        static let playPagerMarginTop: CGFloat = 10

        /// R-11 预览层：海报 104:140，marginTop 20dp，评分 13sp，片名 18sp 3 行，简介 13sp，播放按钮 80×30dp 圆角 15dp，收藏高 30dp
        static let previewPosterRatio: CGFloat = 104.0 / 140.0
        static let previewPosterTopMargin: CGFloat = 20
        static let previewScoreFont: CGFloat = 13
        static let previewTitleFont: CGFloat = 18
        static let previewDescFont: CGFloat = 13
        static let previewPlayWidth: CGFloat = 80
        static let previewPlayHeight: CGFloat = 30
        static let previewPlayCorner: CGFloat = 15
        static let previewFavHeight: CGFloat = 30

        /// R-12 控制层
        static let backButtonSize: CGFloat = 40
        static let netSpeedFont: CGFloat = 14
        static let miniProgressFont: CGFloat = 14
        static let titleFont: CGFloat = 14
        static let countdownSize: CGFloat = 26
        static let countdownHeight: CGFloat = 25
        static let countdownFont: CGFloat = 9
        static let closeScreenSize: CGFloat = 24
        static let speedLabelFont: CGFloat = 12
        static let speedLabelCorner: CGFloat = 12
        static let batteryWidth: CGFloat = 20
        static let batteryHeight: CGFloat = 20
        static let timeWidth: CGFloat = 65
        static let loadingSize: CGFloat = 40
        static let controlButtonSize: CGFloat = 40
        static let playButtonSize: CGFloat = 45
        static let controlButtonCorner: CGFloat = 30
        static let sideButtonSize: CGFloat = 34
        static let sideButtonCorner: CGFloat = 20
        static let seekBarHeight: CGFloat = 20
        static let seekTimeFont: CGFloat = 14
        static let fullScreenWidth: CGFloat = 35
        static let fullScreenHeight: CGFloat = 36
        static let mainPlaySize: CGFloat = 36

        /// R-14 剧情简介卡：海报 104×140，片名 18sp 2 行，简介 12sp 7 行，评分 36sp，收藏 80×30dp 圆角 15dp，来源 12sp marginTop 14，类型 11sp 圆角 12dp，7 个入口 11sp 宽 50dp
        static let introPosterWidth: CGFloat = 104
        static let introPosterHeight: CGFloat = 140
        static let introScoreFont: CGFloat = 36
        static let introDescFont: CGFloat = 12
        static let introSourceFont: CGFloat = 12
        static let introSourceMarginTop: CGFloat = 14
        static let introTypeFont: CGFloat = 11
        static let introTypeCorner: CGFloat = 12
        static let introEntryFont: CGFloat = 11
        static let introEntryWidth: CGFloat = 50

        /// R-15 选集：4 列，集数 13sp 圆角 4dp，线路项高 30dp
        static let seriesColumns: Int = 4
        static let seriesFont: CGFloat = 13
        static let seriesCorner: CGFloat = 4
        static let seriesFlagHeight: CGFloat = 30

        /// R-16 播放设置弹窗：底部 4 按钮高 45dp 圆角 8dp
        static let vodSettingButtonHeight: CGFloat = 45

        /// R-17/R-30 设置行：标题高 40dp 16sp，行高 40dp 14sp，页 paddingTop 35dp
        static let settingPagePaddingTop: CGFloat = 35
        static let settingTitleHeight: CGFloat = 40
        static let settingTitleFont: CGFloat = 16
        static let settingRowHeight: CGFloat = 40
        static let settingRowFont: CGFloat = 14

        /// R-19 轨道弹层：300×250dp，圆角 16dp，标题 16sp，项高 40dp 13sp
        static let trackSheetWidth: CGFloat = 300
        static let trackSheetHeight: CGFloat = 250
        static let trackSheetCorner: CGFloat = 16
        static let trackTitleFont: CGFloat = 16
        static let trackItemHeight: CGFloat = 40
        static let trackItemFont: CGFloat = 13

        /// R-21 历史·收藏：paddingTop 37dp
        static let historyCollectPaddingTop: CGFloat = 37

        /// R-22/R-23 列表：搜索框 14sp 圆角 4dp marginTop 15dp，列表 marginTop 8dp
        static let historySearchFont: CGFloat = 14
        static let historySearchCorner: CGFloat = 4
        static let historySearchMarginTop: CGFloat = 15
        static let historyListMarginTop: CGFloat = 8

        /// R-24 悬浮条：背景 50dp，播放键 35dp，封面 55×55dp
        static let floatBarHeight: CGFloat = 50
        static let floatPlayWidth: CGFloat = 35
        static let floatCover: CGFloat = 55

        /// R-25 我的页：登录区高 180dp marginTop 25dp，4 列设置网格圆角 12dp
        static let myLoginHeight: CGFloat = 180
        static let myLoginMarginTop: CGFloat = 25
        static let myGridColumns: Int = 4
        static let myGridCorner: CGFloat = 12

        /// R-26 功能格：高 80dp，图标 32dp，名称 12sp marginTop 5，角标 8sp 圆角 12dp
        static let myItemHeight: CGFloat = 80
        static let myItemIcon: CGFloat = 32
        static let myItemNameFont: CGFloat = 12
        static let myItemBadgeFont: CGFloat = 8
        static let myItemBadgeCorner: CGFloat = 12

        /// R-27 设置总页：段标题高 40dp 16sp，行高 40dp 14sp
        static let settingSectionTitleHeight: CGFloat = 40

        /// R-28/R-48/R-49/R-50 输入弹窗：内容高 220dp（R-50 为 180dp），输入框 40dp 圆角 10dp 13sp，确认 44dp 圆角 22dp，关闭 33dp marginTop 150dp
        static let inputDialogHeight: CGFloat = 220
        static let passwordDialogHeight: CGFloat = 180
        static let inputFieldHeight: CGFloat = 40
        static let inputFieldCorner: CGFloat = 10
        static let inputFieldFont: CGFloat = 13
        static let dialogConfirmHeight: CGFloat = 44
        static let dialogConfirmCorner: CGFloat = 22
        static let dialogCloseSize: CGFloat = 33
        static let dialogTitleFont: CGFloat = 16

        /// R-29 多仓：内容高 450dp，双栏 1.3 : 2.0，项高 40dp，左滑删除宽 90dp
        static let storeHouseHeight: CGFloat = 450
        static let storeHouseLeftWeight: CGFloat = 1.3
        static let storeHouseRightWeight: CGFloat = 2.0
        static let storeHouseItemHeight: CGFloat = 40
        static let storeHouseDeleteWidth: CGFloat = 90
        static let storeHouseTitleFont: CGFloat = 16
        static let storeHouseAddFont: CGFloat = 14
        static let storeHouseTipFont: CGFloat = 12

        /// R-30 个性化：标题高 35dp 16sp，11 行 40dp
        static let personalityTitleHeight: CGFloat = 35

        /// R-31 添加快捷弹窗：宽 180dp，项高 30dp，paddingTop 10dp
        static let addPopupWidth: CGFloat = 180
        static let addPopupItemHeight: CGFloat = 30

        /// R-31b 线路选集快捷弹窗：宽 350dp
        static let choosePlayPopupWidth: CGFloat = 350

        /// R-32 摇一摇：推荐卡封面 120×180dp，豆瓣角标 10sp 圆角 8dp
        static let shakeCoverWidth: CGFloat = 120
        static let shakeCoverHeight: CGFloat = 180
        static let shakeBadgeFont: CGFloat = 10
        static let shakeBadgeCorner: CGFloat = 8

        /// R-33 赞赏弹窗：标题 18sp marginTop 20，加载圈 30×30
        static let shopTitleFont: CGFloat = 18
        static let shopLoadingSize: CGFloat = 30

        // R-34 / R-35 / R-36 原为直播页度量（paddingTop / logo 区 / 频道名 / 设置图标 / 比例条）。
        // 直播模块已按用户要求在 v2.0.50 build 21 移除，度量随页面一起删除，
        // 见 KNOWN_DIFFERENCES.md「按用户要求移除的功能」。

        /// R-38 本地视频：项高 120dp，复选框 30dp，缩略 4:3，编辑条 50dp
        static let localItemHeight: CGFloat = 120
        static let localCheckboxWidth: CGFloat = 30
        static let localEditBarHeight: CGFloat = 50

        /// R-40 应用列表：搜索框圆角 16dp，刷新 40×40dp，顶部 paddingTop 45dp
        static let apkTopPadding: CGFloat = 45
        static let apkSearchCorner: CGFloat = 16
        static let apkRefreshSize: CGFloat = 40

        /// R-41 更新弹窗：300×440dp，图标 64dp，忽略行 24dp 12sp，按钮圆角 20dp
        static let updateDialogWidth: CGFloat = 300
        static let updateDialogHeight: CGFloat = 440
        static let updateIconSize: CGFloat = 64
        static let updateIgnoreHeight: CGFloat = 24
        static let updateIgnoreFont: CGFloat = 12
        static let updateButtonCorner: CGFloat = 20

        /// R-42 TV 互动：标题 paddingTop 30dp 16sp，提示条高 25dp 圆角 12dp，按钮高 80dp 圆角 12dp，发送按钮 40dp 高圆角 20dp
        static let interactionTopPadding: CGFloat = 30
        static let interactionTipHeight: CGFloat = 25
        static let interactionTipCorner: CGFloat = 12
        static let interactionButtonHeight: CGFloat = 80
        static let interactionButtonCorner: CGFloat = 12
        static let interactionSendHeight: CGFloat = 40
        static let interactionSendCorner: CGFloat = 20

        /// R-43 局域网同步：内容高 470dp，输入框 40dp 12sp，按钮圆角 10dp
        static let syncSheetHeight: CGFloat = 470
        static let syncFieldHeight: CGFloat = 40
        static let syncFieldFont: CGFloat = 12
        static let syncButtonCorner: CGFloat = 10

        /// R-45 WebDAV：宽 340dp，标题 18sp marginTop 16
        static let webDavWidth: CGFloat = 340
        static let webDavTitleFont: CGFloat = 18
        static let webDavTitleMarginTop: CGFloat = 16

        /// R-46 备份还原：内容高 450dp，上传下载图标 80dp
        static let backupSheetHeight: CGFloat = 450
        static let backupIconSize: CGFloat = 80

        /// R-53 简介弹窗：搜索框 30dp 高 12sp，精确按钮 40×24dp，图标 24dp
        static let introSearchHeight: CGFloat = 30
        static let introSearchFont: CGFloat = 12
        static let introExactWidth: CGFloat = 40
        static let introExactHeight: CGFloat = 24
        static let introIconSize: CGFloat = 24

        /// R-54 免责弹窗：标题 18sp，正文 12sp
        static let warningTitleFont: CGFloat = 18
        static let warningBodyFont: CGFloat = 12

        /// 通用网格间距（海报墙 3 列，来自 mobile_item_grid 的实际利用率）
        static let gridSpacing: CGFloat = 8
        static let gridColumns: Int = 3
        static let pageInset: CGFloat = 12
    }

    /// 圆角体系：布局中反复出现的 4 / 8 / 10 / 12 / 14 / 15 / 16 / 20 / 22 / 30。
    enum Corner {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 10
        static let lg: CGFloat = 12
        static let xl: CGFloat = 14
        static let pill: CGFloat = 15
        static let card: CGFloat = 16
        static let round: CGFloat = 20
        static let action: CGFloat = 22
        static let circle: CGFloat = 30
    }
}
