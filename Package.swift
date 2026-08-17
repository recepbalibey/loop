// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Loop",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LoopKit",
            path: "Sources/LoopKit"
        ),
        .executableTarget(
            name: "Loop",
            dependencies: ["LoopKit"],
            path: "Sources/Loop"
        ),
        .testTarget(
            name: "LoopKitTests",
            dependencies: ["LoopKit"],
            path: "Tests/LoopKitTests"
        )
    ]
)
