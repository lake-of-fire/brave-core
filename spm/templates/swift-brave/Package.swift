// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SwiftBrave",
    platforms: [
        .iOS(.v15),
        .macOS("15.0")
    ],
    products: [
        .library(
            name: "BraveAdblock",
            targets: ["BraveAdblock"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "BraveAdblockCore",
            path: "Binary/BraveAdblockCore.xcframework"
        ),
        .target(
            name: "BraveAdblock",
            dependencies: ["BraveAdblockCore"],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedLibrary("c++")
            ]
        ),
        .testTarget(
            name: "BraveAdblockTests",
            dependencies: ["BraveAdblock"]
        )
    ]
)
