// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Daymark",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Daymark", targets: ["DaymarkAppShell"]),
        .executable(name: "daymark", targets: ["DaymarkCLI"]),
        .library(name: "DaymarkCore", targets: ["DaymarkCore"]),
        .library(name: "DaymarkStore", targets: ["DaymarkStore"]),
        .library(name: "DaymarkIndexer", targets: ["DaymarkIndexer"]),
        .library(name: "DaymarkAgents", targets: ["DaymarkAgents"])
    ],
    targets: [
        .executableTarget(
            name: "DaymarkAppShell",
            dependencies: [
                "DaymarkCore",
                "DaymarkStore",
                "DaymarkIndexer",
                "DaymarkAgents"
            ],
            path: "Daymark",
            exclude: [
                "Resources/AppIcon.iconset"
            ],
            resources: [
                .copy("Resources/AppIcon.icns")
            ]
        ),
        .target(
            name: "DaymarkCore",
            path: "Sources/DaymarkCore"
        ),
        .target(
            name: "DaymarkStore",
            dependencies: ["DaymarkCore"],
            path: "Sources/DaymarkStore"
        ),
        .target(
            name: "DaymarkIndexer",
            dependencies: ["DaymarkCore", "DaymarkStore"],
            path: "Sources/DaymarkIndexer"
        ),
        .target(
            name: "DaymarkAgents",
            dependencies: ["DaymarkCore"],
            path: "Sources/DaymarkAgents"
        ),
        .executableTarget(
            name: "DaymarkCLI",
            dependencies: ["DaymarkCore", "DaymarkStore", "DaymarkIndexer", "DaymarkAgents"],
            path: "Sources/daymark"
        ),
        .testTarget(
            name: "DaymarkCoreTests",
            dependencies: ["DaymarkCore"],
            path: "Tests/DaymarkCoreTests"
        ),
        .testTarget(
            name: "DaymarkAgentsTests",
            dependencies: ["DaymarkAgents", "DaymarkCore"],
            path: "Tests/DaymarkAgentsTests"
        ),
        .testTarget(
            name: "DaymarkStoreTests",
            dependencies: ["DaymarkStore"],
            path: "Tests/DaymarkStoreTests"
        ),
        .testTarget(
            name: "DaymarkIndexerTests",
            dependencies: ["DaymarkIndexer", "DaymarkCore", "DaymarkStore"],
            path: "Tests/DaymarkIndexerTests"
        ),
        .testTarget(
            name: "DaymarkCLITests",
            path: "Tests/DaymarkCLITests"
        )
    ]
)
