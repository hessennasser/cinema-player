// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CinemaPlayer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CinemaPlayer", targets: ["CinemaPlayer"]),
    ],
    targets: [
        .executableTarget(name: "CinemaPlayer"),
        .testTarget(name: "CinemaPlayerTests", dependencies: ["CinemaPlayer"]),
    ]
)
