// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkPantherCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MarkPantherCore", targets: ["MarkPantherCore"])
    ],
    targets: [
        .target(name: "MarkPantherCore"),
        .testTarget(name: "MarkPantherCoreTests", dependencies: ["MarkPantherCore"]),
    ]
)
