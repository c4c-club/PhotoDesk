// swift-tools-version:5.9
// PhotoDeskCore —— 零 Apple 依赖的纯逻辑包（Linux 可 build/test，见 AGENTS.md 红线 2 与 docs/03 §5.10）。
// platforms 留空（Linux 无平台约束）；tools-version 5.9 兼容 CI 两条工具链：Xcode 15.4（Swift 5.10）与 Docker swift:6.0-noble（Swift 6.0）。
import PackageDescription

let package = Package(
    name: "PhotoDeskCore",
    products: [
        .library(name: "PhotoDeskCore", targets: ["PhotoDeskCore"])
    ],
    targets: [
        .target(name: "PhotoDeskCore"),
        .testTarget(name: "PhotoDeskCoreTests", dependencies: ["PhotoDeskCore"])
    ]
)
