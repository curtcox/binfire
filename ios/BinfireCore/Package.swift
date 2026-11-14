// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BinfireCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BinfireCore", targets: ["BinfireCore"]),
    ],
    targets: [
        .target(name: "BinfireCore"),
        .testTarget(name: "BinfireCoreTests", dependencies: ["BinfireCore"]),
    ]
)
