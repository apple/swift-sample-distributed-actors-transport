////===----------------------------------------------------------------------===//
////
//// This source file is part of the swift-sample-distributed-actors-transport open source project
////
//// Copyright (c) 2021 Apple Inc. and the swift-sample-distributed-actors-transport project authors
//// Licensed under Apache License v2.0
////
//// See LICENSE.txt for license information
//// See CONTRIBUTORS.txt for the list of swift-sample-distributed-actors-transport project authors
////
//// SPDX-License-Identifier: Apache-2.0
////
////===----------------------------------------------------------------------===//
//
//import _Distributed
//
//import FishyActorTransport
//import ArgumentParser
//import Logging
//
//import func Foundation.sleep
//import struct Foundation.Data
//import class Foundation.JSONDecoder
//
//// ==== ----------------------------------------------------------------------------------------------------------------
//// MARK: Transport specific _remote implementations
////       These would be source generated via a SwiftPM plugin in a real impl
//
//extension ChatRoom: MessageRecipient {
//
//  enum _Message: Sendable, Codable {
//    case join(chatter: Chatter)
//    // TODO: normally also offer: case _unknown
//  }
//
//  // TODO: needs
//    nonisolated func _receiveAny<Encoder>(
//    envelope: Envelope, encoder: Encoder
//) async throws -> Encoder.Output where Encoder: TopLevelEncoder {
//  do {
//    let decoder = JSONDecoder()
//    decoder.userInfo[.actorTransportKey] = self.actorTransport
//
//    let message = try decoder.decode(_Message.self, from: envelope.message)
//    return try await self._receive(message: message, encoder: encoder)
//  } catch {
//    fatalError("\(#function) \(envelope), error: \(error)")
//  }
//}
//
//    nonisolated func _receive<Encoder>(
//    message: _Message, encoder: Encoder
//) async throws -> Encoder.Output where Encoder: TopLevelEncoder {
//  do {
//    switch message {
//    case .join(let chatter):
//      let response = try await self.join(chatter: chatter)
//      return try encoder.encode(response)
//    }
//  } catch {
//    fatalError("Error handling not implemented; \(error)")
//  }
//}
//
//  @_dynamicReplacement (for :_remote_join(chatter:))
//    nonisolated func _fishy_join(chatter: Chatter) async throws -> String {
//  guard let fishy = self.actorTransport as? FishyTransport else {
//    fatalError("""
//               'Generated' \(#function) not compatible with underlying transport.
//               Expected \(FishyTransport.self) but got: \(type(of: self.actorTransport))
//               """)
//  }
//
//  let message = Self._Message.join(chatter: chatter)
//
//  return try await fishy.send(message, to: self.id, expecting: String.self)
//}
//}
//
//extension Chatter: MessageRecipient {
//  enum _Message: Sendable, Codable {
//    case join(room: ChatRoom)
//    case chatRoomMessage(message: String, chatter: Chatter)
//    case chatterJoined(room: ChatRoom, chatter: Chatter)
//    // TODO: normally also offer: case _unknown
//  }
//
//    nonisolated func _receiveAny<Encoder>(
//    envelope: Envelope, encoder: Encoder
//) async throws -> Encoder.Output where Encoder: TopLevelEncoder {
//  let message = try JSONDecoder().decode(_Message.self, from: envelope.message)
//  return try await self._receive(message: message, encoder: encoder)
//}
//
//    nonisolated func _receive<Encoder>(
//    message: _Message, encoder: Encoder
//) async throws -> Encoder.Output where Encoder: TopLevelEncoder {
//  switch message {
//  case .join(let room):
//    fatalError("NOT IMPLEMENTED")
//  case .chatRoomMessage(let message, let chatter):
//    fatalError("NOT IMPLEMENTED")
//  case .chatterJoined(let room, let chatter):
//    try await self.chatterJoined(room: room, chatter: chatter)
//    return try encoder.encode(Optional<String>.none)
//  }
//}
//
//  @_dynamicReplacement (for :_remote_chatterJoined(room:chatter:))
//    nonisolated func _fishy_chatterJoined(room: ChatRoom, chatter: Chatter) async throws {
//  guard let fishy = self.actorTransport as? FishyTransport else {
//    fatalError("""
//               'Generated' \(#function) not compatible with underlying transport.
//               Expected \(FishyTransport.self) but got: \(type(of: self.actorTransport))
//               """)
//  }
//
//  let message = Self._Message.chatterJoined(room: room, chatter: chatter)
//
//  // TODO: sadly source gen has to specialize for the void return here
//  // if we made it possible to pass Void.self we could always return
//  // whatever send has returned here.
//  try await fishy.send(message, to: self.id, expecting: NoResponse.self)
//}
//}
