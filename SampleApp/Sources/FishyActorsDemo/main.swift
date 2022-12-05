//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-sample-distributed-actors-transport open source project
//
// Copyright (c) 2018-2022 Apple Inc. and the swift-sample-distributed-actors-transport project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of swift-sample-distributed-actors-transport project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Distributed

import DistributedSampleHTTP
import ArgumentParser
import NIO
import Logging

import func Foundation.sleep

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Make some chatters and start chatting!

struct Demo: ParsableCommand {
  @Flag(help: "Interactive mode")
  var interactive: Bool = false

  @Flag(help: "Log level used by (all) ActorSystem instances")
  var transportLogLevel: Logger.Level = .info

  mutating func run() throws {
    LoggingSystem.bootstrap(PrettyDemoLogHandler.init)
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

    var keepAlive: Set<Chatter> = []

    // one node to keep the chat rooms:
    let roomNode = try HTTPActorSystem(host: "127.0.0.1", port: 8001, group: group, logLevel: transportLogLevel)
    // multiple nodes for the regional chatters:
    let firstNode = try HTTPActorSystem(host: "127.0.0.1", port: 9002, group: group, logLevel: transportLogLevel)
    let secondNode = try HTTPActorSystem(host: "127.0.0.1", port: 9003, group: group, logLevel: transportLogLevel)

    let room = ChatRoom(topic: "Cute Capybaras", actorSystem: roomNode)

    let alice = Chatter(actorSystem: firstNode)
    let bob = Chatter(actorSystem: secondNode)
    let charlie = Chatter(actorSystem: secondNode)

    for chatter in [alice, bob, charlie] {
      keepAlive.insert(chatter)

      Task {
        // we resolve a reference to `room` using our `p.actorSystem`
        // since all chatters are on other nodes than the chat room,
        // this will always yield a remote reference.
        let remoteRoom = try ChatRoom.resolve(id: room.id, using: chatter.actorSystem)
        try await chatter.join(room: remoteRoom)
      }
    }

    // normally transports will offer `await .park()` functions, but for now just sleep:
    sleep(1000)
    _ = keepAlive

    try group.syncShutdownGracefully()
  }
}

if #available(macOS 12.0, /* Linux */ *) {
  Demo.main()
} else {
  fatalError("Unsupported platform")
}
