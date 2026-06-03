// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIFuelGauge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AIFuelGaugeCore", targets: ["AIFuelGaugeCore"]),
        .executable(name: "aifuelgauge", targets: ["AIFuelGaugeApp"])
    ],
    targets: [
        .target(
            name: "AIFuelGaugeCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "AIFuelGaugeApp",
            dependencies: ["AIFuelGaugeCore"]
        ),
        .testTarget(
            name: "AIFuelGaugeCoreTests",
            dependencies: ["AIFuelGaugeCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
