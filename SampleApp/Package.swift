// swift-tools-version:5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let experimentalFlags = [
  "-Xfrontend", "-enable-experimental-distributed",
]

/******************************************************************************/
/************************************ CAVEAT **********************************/
/******************************************************************************/
// This package is a pretty "silly" example of an actor transport implementation.
// The general outline of components, where resolves and decode/encodes happen
// is approximately the same as in a real implementation, however several shortcuts
// and simplifications were taken to keep the example simple and easier to follow.
//
// The connection management and general HTTP server/client use in this transport
// is not optimal - far from it - and please take care to not copy this implementation
// directly, but rather use it as an inspiration for what COULD be done using this
// language feature.
let package = Package(
    name: "swift-sample-distributed-actors-transport",
    platforms: [
      .macOS(.v12), // because of the 'distributed actor' feature
    ],
    products: [
      // our example app
      .executable(
          name: "FishyActorsDemo",
          targets: [
            "FishyActorsDemo"
          ]
      ),
    ],
    dependencies: [
      .package(name: "sample-fishy-transport", path: "../FishyTransport/"),

      .package(url: "https://github.com/apple/swift-log.git", from: "1.2.0"),
      .package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.0"),
      .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "0.2.0"),
      .package(url: "https://github.com/slashmo/opentelemetry-swift.git", branch: "automatic-context-propagation"),
    ],
    targets: [
      .executableTarget(
          name: "FishyActorsDemo",
          dependencies: [
            .product(name: "FishyActorTransport", package: "sample-fishy-transport"),
            .product(name: "Logging", package: "swift-log"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "Tracing", package: "swift-distributed-tracing"),
            .product(name: "OpenTelemetry", package: "opentelemetry-swift"),
            .product(name: "OtlpGRPCSpanExporting", package: "opentelemetry-swift"),
          ],
          swiftSettings: [
            .unsafeFlags(experimentalFlags)
          ],
          plugins: [
            .plugin(name: "FishyActorTransportPlugin", package: "sample-fishy-transport"),
          ]
      ),

      // ==== Tests -----
      .testTarget(
          name: "FishyActorsDemoTests",
          dependencies: [
            "FishyActorsDemo"
          ],
          swiftSettings: [
            .unsafeFlags(experimentalFlags)
          ]
      ),
    ]
)
