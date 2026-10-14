// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Necaramba",
    platforms: [.macOS(.v12)],
    products: [.library(name: "NecarambaCore", targets: ["NecarambaCore"])],
    targets: [
        .target(name: "NecarambaCore"),
        .testTarget(name: "NecarambaCoreTests", dependencies: ["NecarambaCore"],
                    resources: [.copy("Fixtures")])
    ],
    swiftLanguageVersions: [.v5]
)
