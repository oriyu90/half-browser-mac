// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HalfBrowserMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HalfBrowserMac", targets: ["HalfBrowserMac"]),
    ],
    targets: [
        .executableTarget(
            name: "HalfBrowserMac",
            path: "Sources/HalfBrowserMac"
        ),
    ]
)
