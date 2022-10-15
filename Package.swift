// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "NovaReflection",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "NovaReflection", targets: ["NovaReflection"]),
    ],
    dependencies: [
        .package(name: "NovaCore", path: "../NovaCore/")
    ],
    targets: [
        .systemLibrary(name: "NovaCRT"),
        .target(name: "NovaReflection", dependencies: ["NovaCRT", "NovaCore"]),
        .testTarget(name: "NovaReflectionTests", dependencies: ["NovaReflection"]),
    ]
)
