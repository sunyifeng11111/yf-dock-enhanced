// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockEnhanced",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DockEnhanced", targets: ["DockEnhanced"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "DockCore"),
        .executableTarget(name: "DockEnhanced", dependencies: ["DockCore", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "DockCoreChecks", dependencies: ["DockCore"], path: "Tests/DockCoreChecks")
    ],
    swiftLanguageModes: [.v5]
)
