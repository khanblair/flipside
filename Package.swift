// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Flipside",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "CSQLCipher",
            pkgConfig: "sqlcipher",
            providers: [.brew(["sqlcipher"])]
        ),
        .target(
            name: "FlipsideCore",
            dependencies: ["CSQLCipher"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "Flipside",
            dependencies: ["FlipsideCore"]
        ),
        .testTarget(
            name: "FlipsideCoreTests",
            dependencies: ["FlipsideCore"]
        )
    ]
)
