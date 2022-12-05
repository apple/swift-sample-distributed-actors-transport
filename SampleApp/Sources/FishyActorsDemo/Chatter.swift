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
import Logging

import NIOFoundationCompat

distributed actor Chatter {
  var rooms: [ChatRoom: Set<Chatter>] = [:]

  init(actorSystem: ActorSystem) {
    self.actorSystem = actorSystem
  }

  distributed func join(room: ChatRoom) async throws {
    // join the chat-room
    let welcomeMessage = try await room.join(chatter: self)

    // seems we joined successfully, might as well just add ourselves right away
    rooms[room, default: []].insert(self)

    print("[\(self.id)] \(welcomeMessage)")
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
    print("[\(self.id)] Chatter [\(chatter.id)] joined [\(room.id)] " +
            "(total known members in room \(rooms[room]?.count ?? 0) (including self))")

    let greeting = [
      "Hi there, ",
      "Hello",
      "Hi",
      "Welcome",
      "Long time no see",
      "Hola",
    ].shuffled().first!

    try await room.message("\(greeting) [\(chatter.id)]!", from: self)
  }

  distributed func chatRoomMessage(_ message: String, from chatter: Chatter) {
    print("[\(self.id)]] \(chatter.id) wrote: \(message)")
  }
}
