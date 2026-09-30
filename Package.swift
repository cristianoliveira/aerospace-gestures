// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "aerospace-gestures",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "aerospace-gestures", targets: ["GestureCLI"])],
    targets: [
        .target(name: "GestureCore"),
        .target(name: "GestureInfrastructure", dependencies: ["GestureCore"]),
        .target(name: "GestureCLIPolicy", dependencies: ["GestureCore"]),
        .target(name: "MultitouchBridge", linkerSettings: [.linkedFramework("CoreFoundation")]),
        .target(name: "MultitouchInput", dependencies: ["GestureCore", "MultitouchBridge"]),
        .executableTarget(name: "GestureCLI", dependencies: ["GestureCore", "GestureInfrastructure", "GestureCLIPolicy", "MultitouchInput"]),
        .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"]),
        .testTarget(name: "GestureInfrastructureTests", dependencies: ["GestureInfrastructure"]),
        .testTarget(name: "GestureCLIPolicyTests", dependencies: ["GestureCLIPolicy", "GestureCore"])
    ]
)
