// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Clipjar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Clipjar", targets: ["Clipjar"])],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "ClipjarCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(
            name: "Clipjar",
            dependencies: ["ClipjarCore", .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "ClipjarCoreTests",
            dependencies: ["ClipjarCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
