// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DevOpsStatus",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DevOpsKit"),
        .executableTarget(
            name: "DevOpsStatus",
            dependencies: ["DevOpsKit"]
        ),
        .testTarget(
            name: "DevOpsKitTests",
            dependencies: ["DevOpsKit"]
        ),
    ]
)
