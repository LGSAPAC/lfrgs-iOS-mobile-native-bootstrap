// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiferayKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LiferayKit", targets: ["LiferayKit"]),
    ],
    targets: [
        // No third-party dependencies: Foundation, CryptoKit, Security and AuthenticationServices only.
        .target(name: "LiferayKit"),
        .testTarget(
            name: "LiferayKitTests",
            dependencies: ["LiferayKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
