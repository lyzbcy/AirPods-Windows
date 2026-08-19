// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AirPodsBuddyMac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AirPodsBuddyMac",
            path: "Sources/AirPodsBuddyMac"
        )
    ]
)
