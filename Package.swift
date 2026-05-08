// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "costburn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "costburn",
            path: "Sources/costburn"
        )
    ]
)
