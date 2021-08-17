//===----------------------------------------------------------------------===//
//
// This source file is part of the fishy-actor-transport open source project
//
// Copyright (c) 2018 Apple Inc. and the fishy-actor-transport project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of fishy-actor-transport project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import _Distributed
import FishyActorTransport
import ArgumentParser
import func Foundation.sleep

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Define Distributed Actors

@available(macOS 12.0, *)
distributed actor ChatRoom {
    let topic: String
    var chatters: Set<Chatter> = []

    init(topic: String, transport: ActorTransport) {
        self.topic = topic
    }

    distributed func join(chatter: Chatter) -> String {
        let newChatter = chatters.insert(chatter).inserted

        if newChatter {

        }

        let greeting = newChatter ? "Welcome" : "Welcome BACK"
        return "\(greeting) to the '\(topic)' chat room! (chatters: \(chatters.count))"
    }

    distributed func leave(chatter: Chatter) {
        chatters.remove(chatter)
    }

    /// Announce message to everyone in the chat room.
    distributed func announce(message: String) async {
        await withThrowingTaskGroup(of: Void.self) { group in
            for c in chatters {
                group.addTask {
                    try await c.chatRoomMessage("ANNOUNCEMENT: \(message)")
                }
            }

            // implicitly await all tasks
        }

        print("[\(self.id)] Announcement sent to \(self)")
    }

    /// Announce message to everyone in the chat room.
    distributed func message(_ message: String, from chatter: Chatter) async {
        guard chatters.contains(chatter) else {
            print("Message from unknown chatter (\(chatter)), please 'join' the chat room first!")
            return
        }

        for c in chatters where c != chatter {
            Task {
                try await c.chatRoomMessage("ANNOUNCEMENT: \(message)")
            }
        }
    }
}

@available(macOS 12.0, *)
distributed actor Chatter {

    var rooms: Set<ChatRoom> = []

    distributed func join(room: ChatRoom) async throws {
        let response = try await room.join(chatter: self)
        rooms.insert(room)
        print(response)
    }
    
    distributed func chatRoomMessage(_ message: String) {
        print("[\(self.id)] \(message)")
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Make some chatters and start chatting!

@available(macOS 12.0, *)
struct Demo: ParsableCommand {
    @Flag(help: "Interactive mode")
    var interactive: Bool = false

    mutating func run() throws {
        let roomNode = FishyTransport(host: "127.0.0.1", port: 8001)
        let firstNode = FishyTransport(host: "127.0.0.1", port: 8002)
        let secondNode = FishyTransport(host: "127.0.0.1", port: 8002)

        let room = ChatRoom(topic: "Cute Capybaras", transport: roomNode)

        let alice = Chatter(transport: firstNode)
        let bob = Chatter(transport: secondNode)
        let charlie = Chatter(transport: secondNode)

        for p in [alice, bob, charlie] {
            Task { try await p.join(room: room) }
        }

        // normally transports will ofer `await .park()` functions, but for now just sleep:
        sleep(1000)
    }
}

if #available(macOS 12.0, /* Linux */ *) {
    Demo.main()
} else {
    fatalError("Unsupported platform")
}
