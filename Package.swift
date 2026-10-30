// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MythosTable",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MythosTable", path: "Sources/MythosTable")
    ]
)
