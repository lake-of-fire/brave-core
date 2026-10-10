// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftBrave",
    platforms: [
        .iOS(.v15),
        .macCatalyst(.v15),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "BraveAdblock",
            targets: ["BraveAdblock"]
        ),
        .library(
            name: "WebMedia",
            targets: ["WebMedia"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/lake-of-fire/swiftui-webview.git", branch: "main")
    ],
    targets: [
        .binaryTarget(
            name: "BraveAdblockCore",
            path: "Binary/BraveAdblockCore.xcframework"
        ),
        .target(
            name: "BraveAdblock",
            dependencies: [
                "BraveAdblockCore",
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedLibrary("c++")
            ]
        ),
        .target(
            name: "WebMedia",
            dependencies: [
                .product(name: "SwiftUIWebView", package: "swiftui-webview")
            ],
            path: "Sources/WebMedia",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "BraveAdblockTests",
            dependencies: ["BraveAdblock"]
        ),
        .testTarget(
            name: "WebMediaTests",
            dependencies: ["WebMedia"],
            path: "Tests/WebMediaTests"
        )
    ]
)
