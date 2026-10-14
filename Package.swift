// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Necaramba",
    platforms: [.macOS(.v12)],
    products: [.library(name: "NecarambaCore", targets: ["NecarambaCore"]),
               .library(name: "NecarambaMac", targets: ["NecarambaMac"])],
    targets: [
        .target(name: "NecarambaCore"),
        .systemLibrary(name: "CSQLite"),
        .target(name: "NecarambaMac", dependencies: ["NecarambaCore", "CSQLite"]),
        .testTarget(name: "NecarambaMacTests", dependencies: ["NecarambaMac", "NecarambaCore", "CSQLite"]),
        .testTarget(name: "NecarambaCoreTests", dependencies: ["NecarambaCore"],
                    resources: [.copy("Fixtures")])
    ],
    swiftLanguageVersions: [.v5]
)
