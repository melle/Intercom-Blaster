// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IntercomBlaster",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "IntercomBlaster",
            targets: ["IntercomBlaster"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "VLCKit",
            path: "Vendor/VLCKit.xcframework"
        ),
        .target(
            name: "IntercomBlasterCore",
            path: "Sources/IntercomBlasterCore"
        ),
        .executableTarget(
            name: "IntercomBlaster",
            dependencies: [
                "IntercomBlasterCore",
                "VLCKit"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/IntercomBlaster/Resources/AppInfo.plist"
                ])
            ]
        ),
        .testTarget(
            name: "IntercomBlasterTests",
            dependencies: [
                .target(name: "IntercomBlasterCore")
            ]
        )
    ]
)
