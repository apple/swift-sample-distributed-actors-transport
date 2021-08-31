// swift-tools-version:5.6
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
    name: "swift-sample-distributed-actors-transport",
    platforms: [
      .macOS(.v12),
    ],
    products: [
      // our example app
      .executable(
          name: "FishyActorsDemo",
          targets: [
            "FishyActorsDemo"
          ]
      ),

      // ==== DISTRIBUTED ACTOR TRANSPORT LIBRARY ==== //

      .library(
          name: "FishyActorTransport",
          targets: [
            "FishyActorTransport"
          ]
      ),

      .plugin(
          name: "FishyActorTransportPlugin",
          targets: [
            "FishyActorTransportPlugin"
          ]
      ),

      // would be provided by transport library
      .executable(
          name: "FishyActorsGenerator",
          targets: [
            "FishyActorsGenerator"
          ])
      // ==== END OF DISTRIBUTED ACTOR TRANSPORT LIBRARY ==== //
    ],
    dependencies: [
      // ==== DEPENDENCIES OF DEMO ==== //
      // it would depend on:
      // .package(url: ".../fishy-transport.git", from: "1.0.0"),
      // ==== END OF DEPENDENCIES OF DEMO ==== //

      // ==== DEPENDENCIES OF TRANSPORT ==== //
      .package(url: "https://github.com/apple/swift-log.git", from: "1.2.0"),
      .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
      .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.5.0"),
      .package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.0"),
//      .package(url: "https://github.com/apple/swift-syntax.git", .revision("swift-5.5-DEVELOPMENT-SNAPSHOT-2021-08-28-a")) // TODO: can't use since 'The loaded '_InternalSwiftSyntaxParser' library is from a toolchain that is not compatible with this version of SwiftSyntax'
      .package(url: "https://github.com/apple/swift-syntax.git", branch: "main") // FIXME: needs better versioned tags
      // ==== END OF DEPENDENCIES OF TRANSPORT ==== //
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
          ],
          plugins: [
            "FishyActorTransportPlugin",
          ]
      ),

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

      // === Plugin (provided by transport library) ----

      .plugin(
          name: "FishyActorTransportPlugin",
          capability: .buildTool(),
          dependencies: [
            "FishyActorsGenerator"
          ]
      ),

      .executableTarget(
          name: "FishyActorsGenerator",
          dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
          ]
      ),

      // ==== Tests -----
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
