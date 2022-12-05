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
import Logging

import NIOFoundationCompat

distributed actor ChatRoom {
  let topic: String
  var chatters: Set<Chatter>

  init(topic: String, actorSystem: ActorSystem) {
    self.actorSystem = actorSystem
    self.topic = topic
    self.chatters = []
  }

  distributed func join(chatter: Chatter) async -> String {
    let newChatter = chatters.insert(chatter).inserted
    print("[\(self.id)] Chatter [\(chatter.id)] joined this chat room about: '\(topic)'")

    // not a new member, let's greet it appropriately
    guard newChatter else {
      return "Welcome back to the '\(topic)' chat room! (chatters: \(chatters.count))"
    }

    Task {
      // no need to await for this task, we want to send back the greeting first
      // and then the details about the chatters in the room will be sent.
      for other in chatters where chatter != other {
        try await chatter.chatterJoined(room: self, chatter: other)
      }
    }

    return "Welcome to the '\(topic)' chat room! (chatters: \(chatters.count))"
  }

  distributed func message(_ message: String, from chatter: Chatter) async {
    print("[\(self.id)] Forwarding message from [\(chatter.id)] to \(max(0, chatters.count - 1)) other chatters...")

    /// Forward the message to all other chatters concurrently
    await withThrowingTaskGroup(of: Void.self) { group in
      for other in chatters where chatter != other {
        group.addTask {
          try await other.chatRoomMessage(message, from: chatter)
        }
      }
    }
  }

  distributed func leave(chatter: Chatter) {
    print("[\(self.id)] chatter left the room (\(topic)): \(chatter)")
    chatters.remove(chatter)

    // TODO: notify the others
  }

}
