// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Robyty",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RobytyCore"),
        .executableTarget(
            name: "Robyty",
            dependencies: ["RobytyCore"]
        ),
        .executableTarget(
            name: "RobytyTestRunner",
            dependencies: ["RobytyCore"],
            path: "Tests/RobytyTests"
        )
    ]
)
