// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Utilipilled", platforms: [.macOS(.v13)], products: [
    .executable(name: "Utilipilled", targets: ["Utilipilled"])
], targets: [
    .target(name: "CameraQuietCore"),
    .executableTarget(name: "Utilipilled", dependencies: ["CameraQuietCore"], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("CoreMediaIO"), .linkedFramework("ServiceManagement")]),
    .executableTarget(name: "CameraQuietTests", dependencies: ["CameraQuietCore"], path: "Tests/CameraQuietCoreTests")
])
