// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "dualtap",
    platforms: [.macOS("14.2")],
    targets: [
        .target(name: "DualtapCore", path: "Sources/DualtapCore"),
        .executableTarget(name: "dualtap", dependencies: ["DualtapCore"], path: "Sources/dualtap"),
        .testTarget(name: "DualtapCoreTests", dependencies: ["DualtapCore"], path: "Tests/DualtapCoreTests"),
    ]
)
