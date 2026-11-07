// swift-tools-version:5.9
import PackageDescription

/// U-01 门禁包：验证 cheerio 能否在 JavaScriptCore（macOS 桌面端，与 iOS 同内核）
/// 中运行。这是架构文档定义的阻断级未决项，作为 CI 第一道门（gate-u01）。
/// 详见仓库根 KNOWN_DIFFERENCES.md 的判定记录。
let package = Package(
    name: "U01Gate",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "U01Gate", targets: ["U01Gate"])
    ],
    targets: [
        .target(
            name: "U01Gate",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "U01GateTests",
            dependencies: ["U01Gate"],
            resources: [.copy("Fixtures")]
        )
    ]
)
