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
    name: "sample-fishy-transport",
    platforms: [
      .macOS(.v12), // because of the 'distributed actor' feature
    ],
    products: [
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
    ],
    dependencies: [
      // ==== DEPENDENCIES OF TRANSPORT ==== //
      .package(url: "https://github.com/apple/swift-log.git", from: "1.2.0"),
      .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
      .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.5.0"),
      .package(url: "https://github.com/apple/swift-argument-parser", from: "0.4.0"),
      .package(url: "https://github.com/apple/swift-syntax.git", revision: "b8e4a69237f9dfa362268dddaef8793bc694dc6f"), // TODO: we currently must depend on specific versions here
      .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "0.2.0"),
      // ==== END OF DEPENDENCIES OF TRANSPORT ==== //
    ],
    targets: [
      .target(
          name: "FishyActorTransport",
          dependencies: [
            .product(name: "NIO", package: "swift-nio"),
            .product(name: "_NIOConcurrency", package: "swift-nio"),
            .product(name: "Logging", package: "swift-log"),
            .product(name: "AsyncHTTPClient", package: "async-http-client"),
            .product(name: "Tracing", package: "swift-distributed-tracing"),
          ],
          swiftSettings: [
            .unsafeFlags(experimentalFlags)
          ]),

      // === Plugin -----

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
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxParser", package: "swift-syntax"),
          ]
      ),

      // ==== Tests -----

      .testTarget(
          name: "FishyActorTransportTests",
          dependencies: [
            "FishyActorTransport",
          ],
          swiftSettings: [
            .unsafeFlags(experimentalFlags)
          ]
      ),
      
      .testTarget(
          name: "FishyActorsGeneratorTests",
          dependencies: [
            "FishyActorsGenerator",
          ]
      ),
    ]
)
