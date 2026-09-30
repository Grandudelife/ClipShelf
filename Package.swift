// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipShelf",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ClipShelf", targets: ["ClipShelf"])],
    targets: [
        .target(name: "ClipShelfCore"),
        .executableTarget(name: "ClipShelf", dependencies: ["ClipShelfCore"]),
        .executableTarget(name: "ClipShelfChecks", dependencies: ["ClipShelfCore"], path: "Tests/ClipShelfCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
