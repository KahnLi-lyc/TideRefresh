// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TideRefresh",
    defaultLocalization: "en",
    platforms: [.iOS(.v16)],
    products: [.library(name: "TideRefresh", targets: ["TideRefresh"])],
    targets: [
        .target(name: "TideRefresh", resources: [.process("Resources")]),
        .testTarget(name: "TideRefreshTests", dependencies: ["TideRefresh"]),
    ],
    swiftLanguageModes: [.v6]
)
