//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-sample-distributed-actors-transport open source project
//
// Copyright (c) 2021 Apple Inc. and the swift-sample-distributed-actors-transport project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of swift-sample-distributed-actors-transport project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import _Distributed

import FishyActorTransport
import ArgumentParser
import Logging

import func Foundation.sleep
import struct Foundation.Data
import class Foundation.JSONDecoder
import NIOFoundationCompat

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Define Distributed Actors

distributed actor ChatRoom {
  let topic: String
  var chatters: Set<Chatter>

  init(topic: String, transport: ActorTransport) {
    defer { transport.actorReady(self) } // FIXME(distributed): this will be synthesized (not implemented in compiler yet)

    self.topic = topic
    self.chatters = []
  }

  distributed func join(chatter: Chatter) async -> String {
    let newChatter = chatters.insert(chatter).inserted
    print("[\(self.simpleID)] Chatter [\(chatter.simpleID)] joined this chat room about: '\(topic)'")

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
    print("[\(self.simpleID)] Forwarding message from [\(chatter.simpleID)] to \(max(0, chatters.count - 1)) other chatters...")

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
    print("[\(self.simpleID)] chatter left the room (\(topic)): \(chatter)")
    chatters.remove(chatter)

    // TODO: notify the others
  }

}

distributed actor Chatter {
  var rooms: [ChatRoom: Set<Chatter>] = [:]

  init(transport: ActorTransport) {
    defer { transport.actorReady(self) } // FIXME(distributed): this will be synthesized (not implemented in compiler yet)
  }

  distributed func join(room: ChatRoom) async throws {
    // join the chat-room
    let welcomeMessage = try await room.join(chatter: self)

    // seems we joined successfully, might as well just add ourselves right away
    rooms[room, default: []].insert(self)

    print("[\(self.simpleID)] \(welcomeMessage)")
  }

  // Every chat room we're in will keep us posted about chatters joining the room.
  // This way we can notice when our friend joined the room and send them a direct message etc.
  distributed func chatterJoined(room: ChatRoom, chatter: Chatter) async throws {
    guard chatter != self else {
      // we shouldn't be getting such message, but even if we did, we can ignore
      // the information that we joined the room, because we already know this
      // from the return value from the room.join call.
      return
    }

    rooms[room, default: []].insert(chatter)
    print("[\(self.simpleID)] Chatter [\(chatter.simpleID)] joined [\(room.simpleID)] " +
          "(total known members in room \(rooms[room]?.count ?? 0) (including self))")

    let greeting = [
      "Hi there, ",
      "Hello",
      "Hi",
      "Welcome",
      "Long time no see",
      "Hola",
    ].shuffled().first!

    try await room.message("\(greeting) [\(chatter.simpleID)]!", from: self)
  }

  distributed func chatRoomMessage(_ message: String, from chatter: Chatter) {
    print("[\(self.simpleID)]] \(chatter.simpleID) wrote: \(message)")
  }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Support

// Make logger level codable to use it as option in the Argument Parser main struct.
extension Logger.Level: EnumerableFlag {}

extension ChatRoom: CustomStringConvertible {
  nonisolated var description: String {
    "\(Self.self)(\(id))"
  }

  // Simple ID representation for nice to read log printouts in the demo.
  // Only useful for printing and human operator interaction, not guaranteed to be unique.
  nonisolated var simpleID: String {
    guard let identity = self.id.underlying as? FishyIdentity else {
      return String(describing: self.id)
    }
    let idPrefix = identity.id.prefix { $0 != "-" }
    return ":\(identity.port)/\(identity.typeName)@\(idPrefix)-..."
  }
}

extension Chatter: CustomStringConvertible {
  nonisolated var description: String {
    "\(Self.self)(\(id))"
  }

  // Simple ID representation for nice to read log printouts in the demo.
  // Only useful for printing and human operator interaction, not guaranteed to be unique.
  nonisolated var simpleID: String {
    guard let identity = self.id.underlying as? FishyIdentity else {
      return String(describing: self.id)
    }
    let idPrefix = identity.id.prefix { $0 != "-" }
    return ":\(identity.port)/\(identity.typeName)@\(idPrefix)-..."
  }
}
