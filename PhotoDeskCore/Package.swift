// swift-tools-version:5.9
// PhotoDeskCore —— 零 Apple 依赖的纯逻辑包（Linux 可 build/test，见 AGENTS.md 红线 2 与 docs/03 §5.10）。
// platforms 留空（Linux 无平台约束）；工具链基线：Xcode 16.4 / Swift 5.9+ / Docker swift:6.0-noble。
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
