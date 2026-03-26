// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Spoted",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Spoted",
            path: "Sources/Spoted",
            exclude: ["Info.plist", "Spoted.entitlements"],
            resources: [
                .process("Assets.xcassets")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/Spoted/Info.plist"])
            ]
        )
    ]
)
