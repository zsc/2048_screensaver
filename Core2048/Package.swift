// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Core2048",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "Core2048", targets: ["Core2048"]),
    .executable(name: "core2048-tests", targets: ["Core2048TestRunner"]),
  ],
  targets: [
    .target(
      name: "Core2048"
    ),
    .executableTarget(
      name: "Core2048TestRunner",
      dependencies: ["Core2048"]
    ),
  ]
)
