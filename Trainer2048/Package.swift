// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Trainer2048",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "trainer", targets: ["Trainer2048"])
  ],
  dependencies: [
    .package(path: "../Core2048")
  ],
  targets: [
    .executableTarget(
      name: "Trainer2048",
      dependencies: [
        .product(name: "Core2048", package: "Core2048")
      ]
    )
  ]
)
