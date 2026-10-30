// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Konvolusi",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IRSKit", targets: ["IRSKit"]),
        .executable(name: "irsconv", targets: ["irsconv"]),
        .executable(name: "Konvolusi", targets: ["Konvolusi"]),
    ],
    targets: [
        .target(name: "IRSKit"),
        .executableTarget(name: "irsconv", dependencies: ["IRSKit"]),
        .executableTarget(name: "Konvolusi", dependencies: ["IRSKit"]),
        .testTarget(name: "IRSKitTests", dependencies: ["IRSKit"]),
    ],
    // Real-time audio code is pointer- and callback-heavy; Swift 5 language mode
    // keeps the concurrency checker out of the way without giving up Swift 6 tooling.
    swiftLanguageModes: [.v5]
)
