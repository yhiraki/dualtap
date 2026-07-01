// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "dualtap",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(name: "dualtap", path: "Sources/dualtap")
    ]
)
