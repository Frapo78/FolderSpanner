// swift-tools-version: 5.9
import PackageDescription

// The Foundation-based engine and tests can also run on Linux in CI.
// The SwiftUI executable is included when compiling on macOS.
var products: [Product] = [
    .library(name: "FolderSpannerCore", targets: ["FolderSpannerCore"])
]
var targets: [Target] = [
    .target(name: "FolderSpannerCore", resources: [.process("Resources")]),
    .testTarget(name: "FolderSpannerCoreTests", dependencies: ["FolderSpannerCore"])
]

#if os(macOS)
products.append(.executable(name: "FolderSpanner", targets: ["FolderSpanner"]))
targets.append(.executableTarget(name: "FolderSpanner", dependencies: ["FolderSpannerCore"]))
#endif

let package = Package(
    name: "FolderSpanner",
    platforms: [.macOS(.v13)],
    defaultLocalization: "it",
    products: products,
    targets: targets
)
