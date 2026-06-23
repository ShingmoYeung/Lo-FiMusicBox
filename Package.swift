// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LoFiMusicBox",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LoFiMusicBox", targets: ["LoFiMusicBox"])
    ],
    targets: [
        .executableTarget(
            name: "LoFiMusicBox",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
