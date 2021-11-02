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

import NIO
import NIOHTTP1
import _NIOConcurrency
import AsyncHTTPClient
import Logging
import Tracing

import Foundation // because JSONEncoder and co
import struct Foundation.UUID

@available(OSX 10.15, *)
public protocol MessageRecipient {
  nonisolated func _receiveAny<Encoder, Decoder>(
    envelope: Envelope, encoder: Encoder, decoder: Decoder
  ) async throws -> Encoder.Output where Encoder: TopLevelEncoder, Decoder: TopLevelDecoder
}

public protocol FishyMessage: Codable {
  var functionIdentifier: String { get }
}

private struct AnyMessageRecipient: MessageRecipient {
  weak var actor: AnyObject? // Note: store as AnyActor once supported?

  init<Act: DistributedActor>(actor: Act) {
    self.actor = actor
  }

  nonisolated func _receiveAny<Encoder, Decoder>(
    envelope: Envelope, encoder: Encoder, decoder: Decoder
  ) async throws -> Encoder.Output where Encoder: TopLevelEncoder, Decoder: TopLevelDecoder {
    guard let anyRecipient = self.actor else {
      throw RecipientReleasedError(recipient: envelope.recipient)
    }
    guard let recipient = anyRecipient as? MessageRecipient else {
      fatalError("Cannot cast \(anyRecipient) TO \(MessageRecipient.self)")
    }
    return try await recipient._receiveAny(envelope: envelope, encoder: encoder, decoder: decoder)
  }
}

@available(OSX 10.15, *)
public final class FishyTransport: ActorTransport, @unchecked Sendable, CustomStringConvertible {

  // server / bind configuration
  let host: String
  let port: Int

  let log: Logger

  // managed local actors
  private let lock: Lock
  private var managed: [AnyActorIdentity: AnyMessageRecipient]

  // networking infra
  private let group: EventLoopGroup
  private var server: FishyServer!
  private let client: HTTPClient

  public init(host: String, port: Int, group: EventLoopGroup, logLevel: Logger.Level? = nil) throws {
    self.host = host
    self.port = port

    if let level = logLevel {
      var log = Logger(label: "\(host):\(port)")
      log.logLevel = level
      self.log = log
    } else {
      log = Logger(label: "noop") { _ in
        SwiftLogNoOpLogHandler()
      }
    }

    self.group = group
    self.lock = Lock()
    self.managed = [:]

    // This naive transport implementation reuses HTTP as the underlying transport layer.
    // Real implementations are likely to use specialized protocols, however it is simple
    // to reuse the existing HTTP client for this example application.
    //
    // we're reusing the EL, just so we have few threads involved in the sample app
    self.client = HTTPClient(eventLoopGroupProvider: .shared(group.next()))

    self.server = FishyServer(group: group, transport: self)
    try self.server.bootstrap(host: host, port: port)
    log.info("Bound to: \(self.server.channel!.localAddress!)")
  }

  public func decodeIdentity(from decoder: Decoder) throws -> AnyActorIdentity {
    let container = try decoder.singleValueContainer()

    // TODO: validate if it actually is a FishyIdentity etc.
    let identity = try container.decode(FishyIdentity.self)

    return AnyActorIdentity(identity)
  }

  public func resolve<Act>(_ identity: AnyActorIdentity, as actorType: Act.Type)
  throws -> Act? where Act: DistributedActor {
    let resolved: Act? = nil
    log.info("FishyTransport::resolve(\(identity), as: \(actorType)) -> \(String(describing: resolved))")
    return resolved
  }

  public func assignIdentity<Act>(_ actorType: Act.Type) -> AnyActorIdentity where Act: DistributedActor {
    let id = AnyActorIdentity(FishyIdentity(transport: self, type: "\(actorType)"))
    log.debug("FishyTransport::assignIdentity(\(actorType)) -> \(id)")
    return id
  }

  public func actorReady<Act>(_ actor: Act) where Act: DistributedActor {
    log.debug("FishyTransport::actorReady(\(actor))")
    guard actor is MessageRecipient else {
      fatalError("\(actor) is not a MessageRecipient! Missing conformance / source generation?")
    }

    self.lock.withLockVoid {
      let anyRecipient = AnyMessageRecipient(actor: actor)
      self.managed[actor.id] = anyRecipient
    }
  }

  public func resignIdentity(_ id: AnyActorIdentity) {
    log.debug("FishyTransport::resignIdentity(\(id))")
    self.lock.withLockVoid {
      self.managed.removeValue(forKey: id)
    }
  }

  public func send<Message: Sendable & FishyMessage>(
      _ message: Message, to recipient: AnyActorIdentity,
      expecting responseType: Void.Type
  ) async throws -> Void {
    _ = try await self.send(message, to: recipient, expecting: NoResponse.self)
  }

  public func send<Message: Sendable & FishyMessage, Response: Sendable & Codable>(
    _ message: Message, to recipient: AnyActorIdentity,
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    log.debug("Send message", metadata: [
      "message": "\(message)",
      "recipient": "\(recipient)",
      "responseType": "\(responseType)",
    ])

    let encoder = JSONEncoder()
    encoder.userInfo[.actorTransportKey] = self

    let decoder = JSONDecoder()
    decoder.userInfo[.actorTransportKey] = self

    let response = try await sendEnvelopeRequest(message, to: recipient, encoder: encoder)

    // Short-circuit if we allowed Void to be passed as the `responseType`...
    // Right now we don't since it is not Codable, but we could consider it.
    if (responseType == NoResponse.self) {
      return (NoResponse._instance as! Response)
    }

    guard let responseBody = response.body else {
      log.debug("No response body")
      throw FishyMessageError.missingResponsePayload(expected: responseType)
    }

    do {
      log.debug("try decoding as \(Response.self)")
      return try decoder.decode(Response.self, from: responseBody)
    } catch {
      throw FishySerializationError.unableToDecodeResponse(responseBody, expectedType: Response.self, error)
    }
  }

  private func sendEnvelopeRequest<Message: Sendable & FishyActorTransport.FishyMessage>(
      _ message: Message, to recipient: AnyActorIdentity, 
      encoder: JSONEncoder
  ) async throws -> HTTPClient.Response {
    try await InstrumentationSystem.tracer.withSpan(message.functionIdentifier) { span in
      // Prepare the message envelope
      var envelope = try Envelope(recipient: recipient, message: message)

      // inject metadata values to propagate for distributed tracing
      if let baggage = Baggage.current {
        InstrumentationSystem.instrument.inject(baggage, into: &envelope.metadata, using: MessageEnvelopeMetadataInjector())
      }

      var recipientURI: String.SubSequence = "\(recipient.underlying)"

      let requestData = try encoder.encode(envelope)
      log.debug("Send envelope request", metadata: [
        "envelope": "\(String(data: requestData, encoding: .utf8)!)",
        "recipient": "\(recipientURI)"
      ])

      recipientURI = recipientURI.dropFirst("fishy://".count) // our transport is super silly, and abuses http for its messaging
      let requestURI = String("http://" + recipientURI)

      let response = try await sendHTTPRequest(requestURI: requestURI, requestData: requestData)
      log.debug("Received response \(response)", metadata: [
        "response/payload": "\(response.body?.getString(at: 0, length: response.body?.readableBytes ?? 0) ?? "")"
      ])

      return response
    }
  }

  private func sendHTTPRequest(requestURI: String, requestData: Data) async throws -> HTTPClient.Response {
    try await InstrumentationSystem.tracer.withSpan("HTTP POST", ofKind: .client) { span in
      let request = try HTTPClient.Request(
          url: requestURI,
          method: .POST,
          headers: [
            "Content-Type": "application/json"
          ],
          body: .data(requestData))
      span.attributes["http.method"] = "POST"
      span.attributes["http.url"] = requestURI

      let future = client.execute(
          request: request,
          deadline: .now() + .seconds(3)) // A real implementation would allow configuring these (i.e. pick up a task-local deadline)

      let response = try await future.get()
      span.attributes["http.status_code"] = Int(response.status.code)
      return response
    }
  }

  /// Actually deliver the message to the local recipient
  func deliver(envelope: Envelope) async throws -> Data {
    var baggage = Baggage.current ?? .topLevel
    InstrumentationSystem.instrument.extract(
        envelope.metadata,
        into: &baggage,
        using: MessageEnvelopeMetadataExtractor()
    )

    return try await Baggage.$current.withValue(baggage) {
      log.debug("Deliver to \(envelope.recipient)")

      guard let known = resolveRecipient(of: envelope) else {
        throw handleDeadLetter(envelope)
      }

      log.debug("Delivering to local instance: \(known)", metadata: [
        "envelope": "\(envelope)",
        "recipient": "\(known)",
      ])

      // In a real implementation coders would often be configurable on transport level.
      //
      // The transport must ensure to store itself in the user info offered to receive
      // as it may need to attempt to decode actor references.
      let encoder = JSONEncoder()
      let decoder = JSONDecoder()
      encoder.userInfo[.actorTransportKey] = self
      decoder.userInfo[.actorTransportKey] = self

      do {
        return try await known._receiveAny(envelope: envelope, encoder: encoder, decoder: decoder)
      } catch {
        fatalError("Failed to deliver: \(error)")
      }
    }
  }

  private func resolveRecipient(of envelope: Envelope) -> MessageRecipient? {
    lock.withLock {
      self.managed[envelope.recipient]
    }
  }

  /// The recipient of the envelope does not exist, or has already terminated.
  ///
  /// A dead letter is a message which is unable to be delivered, and must be
  /// handled using some other means, e.g. by logging information about it, or
  /// dropping it immediately or discarding it.
  ///
  /// The sender of such dead letter should be notified that it failed to reach
  /// its intended recipient.
  private func handleDeadLetter(_ envelope: Envelope) -> Error {
    log.warning("Not known recipient (dead letter encountered): \(envelope.recipient)")
    lock.withLockVoid {
      for item in managed {
        log.warning(" KNOWN: \(item)")
      }
        log.warning("WANTED: \(envelope.recipient)")
    }
    return UnknownRecipientError(recipient: envelope.recipient)
  }

  public func untilShutdown() async throws {
    // This will never unblock as we don't close the ServerChannel
    try await self.server.channel?.closeFuture.get()
  }

  public func syncShutdownGracefully() {
    try! group.syncShutdownGracefully()
  }

  public var description: String {
    "\(Self.self)(\(host):\(port))"
  }
}

/// A very naive (fishy even!) actor identity implementation.
///
/// It uniquely identifies a fishy distributed actor in the system.
@available(OSX 10.15, *)
public struct FishyIdentity: ActorIdentity, CustomStringConvertible, Hashable {
  public let proto: String
  public let host: String
  public let port: Int
  public let typeName: String
  public let id: String

  /// Create specific identity.
  init(host: String, port: Int, typeName: String, id: String) {
    self.proto = "fishy"
    self.host = host
    self.port = port
    self.typeName = typeName
    self.id = id
  }

  /// Create new unique identity.
  init(transport: FishyTransport, type: String) {
    self.proto = "fishy"
    self.host = transport.host
    self.port = transport.port
    self.typeName = type
    self.id = UUID().uuidString
  }


  public var description: String {
    "\(proto)://\(host):\(port)/\(typeName)@\(id)"
  }
}

public struct Envelope: Sendable, Codable {
  enum CodingKeys: CodingKey {
    case recipient
    case message
    case metadata
  }

  public let recipient: AnyActorIdentity
  public let message: Data
  public var metadata: [String: String]

  // Naive implementation, encodes the `message` as bytes blob using the `encoder`.
  init<Message: Codable>(recipient: AnyActorIdentity, message: Message, encoder: JSONEncoder = JSONEncoder()) throws {
    self.recipient = recipient
    self.message = try encoder.encode(message)
    self.metadata = [:]
  }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Serialization

/// Represents a `void` return type of a distributed call.
/// Pass this to `send` to avoid decoding any value from the response.
public enum NoResponse: Codable, FishyActorTransport.FishyMessage {
  case _instance
  
  public var functionIdentifier: String { "noResponse" }
}

extension DistributedActor {
  public nonisolated var requireFishyTransport: FishyTransport {
    guard let fishy = actorTransport as? FishyTransport else {
      fatalError("""
                 'Generated' \(#function) not compatible with underlying transport.
                 Expected \(FishyTransport.self) but got: \(type(of: self.actorTransport))
                 """)
    }
    return fishy
  }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Errors

public enum FishySerializationError: ActorTransportError {
  case missingActorTransport
  case unableToDecodeResponse(ByteBuffer, expectedType: Any.Type, Error)
}

public enum FishyMessageError: ActorTransportError {
  case missingResponsePayload(expected: Any.Type)
  case voidReturn
}

public struct UnknownRecipientError: ActorTransportError {
  let recipient: AnyActorIdentity
}

public struct RecipientReleasedError: ActorTransportError {
  let recipient: AnyActorIdentity
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Instrumentation

struct MessageEnvelopeMetadataInjector: Injector {
  func inject(_ value: String, forKey key: String, into metadata: inout [String: String]) {
    metadata[key] = value
  }
}

struct MessageEnvelopeMetadataExtractor: Extractor {
  func extract(key: String, from metadata: [String: String]) -> String? {
    metadata[key]
  }
}
