// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SteamControllerBridge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SteamControllerBridge",
            path: "Sources/SteamControllerBridge",
            swiftSettings: [
                .unsafeFlags(["-I", "Sources/CSDL3/include"]),
                .unsafeFlags(["-I/opt/homebrew/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib"]),
                .linkedLibrary("SDL3")
            ]
        )
    ]
)
