// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DingDongBlaster",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "DingDongBlaster",
            targets: ["DingDongBlaster"]
        )
    ],
    targets: [
        .executableTarget(
            name: "DingDongBlaster",
            path: "Sources",
            sources: ["DingDongBlaster"],
            resources: []
        ),
        .testTarget(
            name: "DingDongBlasterTests",
            dependencies: [
                .target(name: "DingDongBlaster")
            ],
            path: "Tests",
            sources: ["DingDongBlasterTests"]
        )
    ]
)
