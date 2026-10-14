// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TDMFast",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TDMFast", targets: ["TDMFast"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "TDMFast",
            dependencies: [],
            path: "Sources/TDMFast",
            resources: []
        )
    ]
)
