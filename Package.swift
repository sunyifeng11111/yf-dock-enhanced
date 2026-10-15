// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockEnhanced",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DockEnhanced", targets: ["DockEnhanced"])],
    targets: [
        .target(name: "DockCore"),
        .executableTarget(name: "DockEnhanced", dependencies: ["DockCore"]),
        .executableTarget(name: "DockCoreChecks", dependencies: ["DockCore"], path: "Tests/DockCoreChecks")
    ],
    swiftLanguageModes: [.v5]
)
