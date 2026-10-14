// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Necaramba",
    platforms: [.macOS(.v12)],
    products: [.library(name: "NecarambaCore", targets: ["NecarambaCore"]),
               .library(name: "NecarambaMac", targets: ["NecarambaMac"]),
               .executable(name: "ReplayRunner", targets: ["ReplayRunner"]),
               .executable(name: "CorpusRunner", targets: ["CorpusRunner"])],
    targets: [
        .target(name: "NecarambaCore"),
        .executableTarget(name: "CorpusRunner", dependencies: ["NecarambaCore"], path: "Tools/CorpusRunner"),
        .executableTarget(name: "ReplayRunner", dependencies: ["NecarambaCore", "NecarambaMac"], path: "Tools/ReplayRunner"),
        .systemLibrary(name: "CSQLite"),
        .target(name: "NecarambaMac", dependencies: ["NecarambaCore", "CSQLite"]),
        .testTarget(name: "NecarambaMacTests", dependencies: ["NecarambaMac", "NecarambaCore", "CSQLite"]),
        .testTarget(name: "NecarambaCoreTests", dependencies: ["NecarambaCore"],
                    resources: [.copy("Fixtures")])
    ],
    swiftLanguageVersions: [.v5]
)
