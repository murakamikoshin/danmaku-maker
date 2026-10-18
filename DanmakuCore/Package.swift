// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DanmakuCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "DanmakuCore", targets: ["DanmakuCore"]),
    ],
    targets: [
        .target(name: "DanmakuCore"),
        // 公式ステージの検証用ボット（アプリには入らない）
        .executableTarget(name: "StageBot", dependencies: ["DanmakuCore"]),
        .testTarget(name: "DanmakuCoreTests", dependencies: ["DanmakuCore"],
                    resources: [.copy("Resources")]),
    ]
)
