// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "aerospace-gestures",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "aerospace-gestures", targets: ["GestureCLI"])],
    targets: [
        .target(name: "GestureCore"),
        .target(name: "MultitouchBridge", linkerSettings: [.linkedFramework("CoreFoundation")]),
        .executableTarget(name: "GestureCLI", dependencies: ["GestureCore", "MultitouchBridge"]),
        .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"])
    ]
)
