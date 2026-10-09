// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KilnWatchCore",
    platforms: [.iOS("27.0"), .macOS(.v26)],
    products: [
        .library(name: "KilnWatchCore", targets: ["KilnWatchCore"]),
    ],
    targets: [
        .target(name: "KilnWatchCore", resources: [.process("Fixtures")]),
        .testTarget(name: "KilnWatchCoreTests", dependencies: ["KilnWatchCore"]),
    ],
    swiftLanguageModes: [.v6]
)
