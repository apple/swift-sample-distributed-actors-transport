// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

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
    name: "swift-sample-distributed-actors",
    platforms: [
      .macOS(.v13), // because of the 'distributed actor' feature
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
      .package(name: "distributed-sample-http", path: "../DistributedSampleHTTP/"),

      .package(url: "https://github.com/apple/swift-log.git", from: "1.2.0"),
      .package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.0"),
    ],
    targets: [
      .executableTarget(
          name: "FishyActorsDemo",
          dependencies: [
            .product(name: "DistributedSampleHTTP", package: "distributed-sample-http"),
            .product(name: "Logging", package: "swift-log"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
          ]
      ),
    ]
)
