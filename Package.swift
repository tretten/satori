// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Satori",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Satori",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Satori",
            // Same reasoning as the canvas app next door: the whole interface is
            // main-thread by nature, and Swift 6's strict isolation buys nothing
            // here but ceremony.
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Sparkle is linked weakly so a web app — a copy of this binary
            // that never updates itself — can leave the framework out and
            // still launch. Only UpdaterController touches it, and a web app
            // never makes one.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "Sparkle"])]
        )
    ]
)
