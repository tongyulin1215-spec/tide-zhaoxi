// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Cre",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "CreCore", targets: ["CreCore"]),
    ],
    targets: [
        .target(name: "CreCore", path: "Sources/CreCore"),
        .testTarget(name: "CreCoreTests", dependencies: ["CreCore"], path: "Tests/CreCoreTests"),
    ]
)
