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
    name: "distributed-sample-http",
    platforms: [
        .macOS(.v13), // because of the 'distributed actor' feature
    ],
    products: [
      .library(
          name: "DistributedSampleHTTP",
          targets: [
            "DistributedSampleHTTP"
          ]
      ),
    ],
    dependencies: [
      .package(url: "https://github.com/apple/swift-log.git", from: "1.4.1"),
      .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
      .package(url: "https://github.com/swift-server/async-http-client.git", branch: "1.13.1"),
    ],
    targets: [
      .target(
          name: "DistributedSampleHTTP",
          dependencies: [
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "_NIOConcurrency", package: "swift-nio"),
            .product(name: "Logging", package: "swift-log"),
            .product(name: "AsyncHTTPClient", package: "async-http-client"),
          ]
      ),

      // ==== Tests -----

      .testTarget(
          name: "DistributedSampleHTTPTests",
          dependencies: [
            "DistributedSampleHTTP",
          ]
      ),
    ]
)
