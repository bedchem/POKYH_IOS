// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PokyhKit",
    defaultLocalization: "de",
    platforms: [.iOS("26.0"), .watchOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "PokyhCore", targets: ["PokyhCore"]),
        .library(name: "PokyhDesign", targets: ["PokyhDesign"]),
    ],
    targets: [
        // Models, clients, storage, strings. No UI, so it also runs on the Mac for `swift test`.
        .target(name: "PokyhCore"),
        // Tokens, components and the pixel mascot, shared by app, widgets and watch.
        .target(name: "PokyhDesign", dependencies: ["PokyhCore"]),
        .testTarget(
            name: "PokyhCoreTests",
            dependencies: ["PokyhCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
