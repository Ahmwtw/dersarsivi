// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DersArsiviCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DersArsiviCore", targets: ["DersArsiviCore"]),
    ],
    targets: [
        .target(name: "DersArsiviCore"),
        .testTarget(name: "DersArsiviCoreTests", dependencies: ["DersArsiviCore"]),
    ]
)
