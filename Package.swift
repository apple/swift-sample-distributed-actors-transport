// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "fishy-actor-transport",
    products: [
        .executable(
            name: "FishyActorsDemo",
            targets: [
                "FishyActorsDemo"
            ]
        )
    ],
    dependencies: [
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
              .unsafeFlags(["-Xfrontend" , "-enable-experimental-concurrency",
                            "-Xfrontend", "-validate-tbd-against-ir=none"])
            ]),
        .target(
            name: "FishyActorTransport",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ],
            swiftSettings: [
              .unsafeFlags(["-Xfrontend" , "-enable-experimental-concurrency",
                            "-Xfrontend", "-validate-tbd-against-ir=none"
              ])
            ]),
//        .testTarget(
//            name: "fishy-actor-transportTests",
//            dependencies: ["fishy-actor-transport"]),
    ]
)
