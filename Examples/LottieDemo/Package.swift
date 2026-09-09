// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TideRefreshLottieDemo",
    platforms: [.iOS(.v16)],
    products: [.library(name: "TideRefreshLottieDemo", targets: ["TideRefreshLottieDemo"])],
    dependencies: [
        .package(name: "TideRefresh", path: "../.."),
        .package(url: "https://github.com/airbnb/lottie-ios.git", exact: "4.5.2"),
    ],
    targets: [
        .target(
            name: "TideRefreshLottieDemo",
            dependencies: [
                .product(name: "TideRefresh", package: "TideRefresh"),
                .product(name: "Lottie", package: "lottie-ios"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
