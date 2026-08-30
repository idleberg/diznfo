// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "NFOKit",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "NFOKit", targets: ["NFOKit"])
  ],
  targets: [
    .target(name: "NFOKit"),
    .testTarget(name: "NFOKitTests", dependencies: ["NFOKit"]),
  ]
)
