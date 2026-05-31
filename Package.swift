// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "macos-remote",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "controlled", targets: ["Controlled"]),
        .executable(name: "controller", targets: ["Controller"]),
    ],
    targets: [
        .executableTarget(
            name: "Controlled",
            path: "Sources/Controlled",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("Network"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreMedia"),
            ]
        ),
        .executableTarget(
            name: "Controller",
            path: "Sources/Controller",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("Network"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreMedia"),
            ]
        ),
    ]
)
