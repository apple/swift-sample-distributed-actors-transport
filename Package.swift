// swift-tools-version:5.5
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
/******************************************************************************/
let package = Package(
    name: "swift-sample-distributed-actors-transport",
    platforms: [
      .macOS(.v12),
    ],
    products: [
      .executable(
          name: "FishyActorsDemo",
          targets: [
            "FishyActorsDemo"
          ]
      )
    ],
    dependencies: [
      .package(url: "https://github.com/apple/swift-log.git", from: "1.2.0"),
      .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
      .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.5.0"),
      .package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.0"),
    ],
    targets: [
      .executableTarget(
          name: "FishyActorsDemo",
          dependencies: [
            "FishyActorTransport",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
          ],
          swiftSettings: [
            .unsafeFlags([
              "-Xfrontend", "-enable-experimental-distributed",
              "-Xfrontend", "-validate-tbd-against-ir=none", // FIXME: slight issue in distributed synthesis
              "-Xfrontend", "-disable-availability-checking", // availability does not matter since _Distributed is not part of the SDK at this point
            ])
          ]),
      .target(
          name: "FishyActorTransport",
          dependencies: [
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "_NIOConcurrency", package: "swift-nio"),
            .product(name: "Logging", package: "swift-log"),
            .product(name: "AsyncHTTPClient", package: "async-http-client"),
          ],
          swiftSettings: [
            .unsafeFlags([
              "-Xfrontend", "-enable-experimental-distributed",
              "-Xfrontend", "-validate-tbd-against-ir=none",
              "-Xfrontend", "-disable-availability-checking", // availability does not matter since _Distributed is not part of the SDK at this point
            ])
          ]),
      .testTarget(
          name: "FishyActorsDemoTests",
          dependencies: [
            "FishyActorsDemo"
          ],
          swiftSettings: [
            .unsafeFlags([
              "-Xfrontend", "-enable-experimental-distributed",
              "-Xfrontend", "-validate-tbd-against-ir=none",
              "-Xfrontend", "-disable-availability-checking", // availability does not matter since _Distributed is not part of the SDK at this point
            ])
          ]
      ),
    ]
)
