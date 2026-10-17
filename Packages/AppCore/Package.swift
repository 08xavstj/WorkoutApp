// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AppCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "AppCore", targets: ["AppCore"])
    ],
    targets: [
        .target(name: "AppCore"),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"])
    ]
)
