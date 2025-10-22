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
        .binaryTarget(
            name: "VLCKit",
            path: "Vendor/VLCKit.xcframework"
        ),
        .target(
            name: "DingDongBlasterCore",
            path: "Sources/DingDongBlasterCore"
        ),
        .executableTarget(
            name: "DingDongBlaster",
            dependencies: [
                "DingDongBlasterCore",
                "VLCKit"
            ]
        ),
        .testTarget(
            name: "DingDongBlasterTests",
            dependencies: [
                .target(name: "DingDongBlasterCore")
            ]
        )
    ]
)
