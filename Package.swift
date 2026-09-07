// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PinTerm",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PinTerm", targets: ["PinTerm"])],
    dependencies: [
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", from: "1.5.2"),
    ],
    targets: [
        .executableTarget(name: "PinTerm", dependencies: [
            .product(name: "GhosttyTerminal", package: "libghostty-spm"),
        ]),
        .testTarget(name: "PinTermTests", dependencies: ["PinTerm"]),
    ]
)
