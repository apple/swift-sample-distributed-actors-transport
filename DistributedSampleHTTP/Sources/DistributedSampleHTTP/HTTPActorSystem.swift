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

@_exported import Distributed
import Logging
import NIO
import NIOCore
import NIOFoundationCompat
import NIOHTTP1
import Foundation
import AsyncHTTPClient

public final class HTTPActorSystem: DistributedActorSystem, @unchecked Sendable {
  public typealias InvocationDecoder = HTTPInvocationDecoder
  public typealias InvocationEncoder = HTTPInvocationEncoder
  public typealias SerializationRequirement = any Codable
  public typealias ResultHandler = HTTPInvocationResultHandler
  public typealias CallID = UUID

  // server / bind configuration
  let bindHost: String
  let bindPort: Int

  public let mode: Mode

  public let log: Logger

  private let group: EventLoopGroup

  // managed local actors
  private let lock: Lock = Lock()
  private var reserved: Set<ActorID> = []
  private var managed: [ActorID: any DistributedActor] = [:]

  typealias HTTPRootPath = String
  private var onDemandFactories: [HTTPRootPath: (ActorID) async -> any DistributedActor] = [:]

  private var server: HTTPActorSystemServer!
  private let client: HTTPClient!

  public enum Mode: Sendable {
    case server(host: String, port: Int)
    case client

    var isServer: Bool {
      switch self {
      case .server: return true
      default: return false
      }
    }
    var isClient: Bool {
      switch self {
      case .client: return true
      default: return false
      }
    }
  }

  public init(host: String, port: Int, group: MultiThreadedEventLoopGroup, logLevel: Logger.Level = .info) throws {
    let mode = Mode.server(host: host, port: port)
    self.mode = mode
    self.group = group

    switch mode {
    case .client:
      self.bindHost = "0.0.0.0"
      self.bindPort = 0

      var log = Logger(label: "HTTPActorSystem::Client")
      log.logLevel = logLevel
      self.log = log

      self.client = HTTPClient(eventLoopGroupProvider: .shared(group))
      log.info("Initialized \(Self.self) in [Client] mode")

    case .server(let host, let port):
      self.bindHost = host
      self.bindPort = port

      var log = Logger(label: "HTTPActorSystem::Server")
      log.logLevel = logLevel
      self.log = log

      self.client = HTTPClient(eventLoopGroupProvider: .shared(group))
      self.server = HTTPActorSystemServer(group: group, system: self)
      try self.server.bootstrap(host: host, port: port)
      log.info("Initialized \(Self.self) in [Server] mode, bound to: \(self.server.channel!.localAddress!)")
    }
  }

  public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act? where Act: DistributedActor, ActorID == Act.ID {
    self.lock.withLock {
      let known = self.managed[id]
      return known as? Act
    }
  }

  public func assignID<Act>(_ actorType: Act.Type) -> ActorID where Act: DistributedActor, ActorID == Act.ID {
    self.lock.withLock {
      var id: ActorID
      if let predefinedID = HTTPActorSystem.predefinedID {
        id = predefinedID
      } else {
        let path = "\(actorType)"
        let uuid = UUID()
        id = ActorID(host: self.bindHost, port: self.bindPort, path: path, uuid: uuid)
      }
      self.reserved.insert(id)
      return id
    }
  }

  public func actorReady<Act>(_ actor: Act) where Act: DistributedActor, ActorID == Act.ID {
    self.lock.lock()
    defer { self.lock.unlock() }

    guard self.reserved.remove(actor.id) != nil else {
      fatalError("Attempted to ready actor for unknown ID! Was: \(actor.id), reserved (known) IDs: \(self.reserved)")
    }

    self.log.debug("Actor ready: \(actor.id)", metadata: [
      "actor/id": "\(actor.id)",
      "actor/type": "\(Act.self)"
    ])
    self.managed[actor.id] = actor

  }

  public func remoteCall<Act, Err, Res>(
          on actor: Act,
          target: RemoteCallTarget,
          invocation: inout InvocationEncoder,
          throwing: Err.Type,
          returning: Res.Type
  ) async throws -> Res
          where Act: DistributedActor,
          Act.ID == ActorID,
          Err: Error,
          Res: Codable {
    log.debug("Remote call on [\(actor.id)] to [\(target)]", metadata: [
      "target": "\(target)",
      "actor/id": "\(actor.id)",
      "response/type": "\(Res.self)",
    ])


    let decoder = JSONDecoder()
    decoder.userInfo[.actorSystemKey] = self

    let response = try await sendEnvelopeRequest(invocation, target: target, to: actor.id)

    guard let responseBody = response.body else {
      log.debug("No response body")
      throw HTTPActorSystemError.missingResponsePayload(expected: Res.self)
    }

    do {
      log.debug("try decoding as \(Res.self)")
      return try decoder.decode(Res.self, from: responseBody)
    } catch {
      throw HTTPActorSystemError.unableToDecodeResponse(body: responseBody, expectedType: Res.self, error: error)
    }    }

  public func remoteCallVoid<Act, Err>(
          on actor: Act,
          target: RemoteCallTarget,
          invocation: inout InvocationEncoder,
          throwing: Err.Type
  ) async throws where Act: DistributedActor,
  Act.ID == ActorID,
  Err: Error {
    log.debug("Remote call on [\(actor.id)] to [\(target)]", metadata: [
      "target": "\(target)",
      "actor/id": "\(actor.id)",
      "response/type": "Void",
    ])


    let decoder = JSONDecoder()
    decoder.userInfo[.actorSystemKey] = self

    let response = try await sendEnvelopeRequest(invocation, target: target, to: actor.id)

    guard 200 ..< 300 ~= response.status.code else {
      log.debug("Bad status code: \(response.status.code)")
      throw HTTPActorSystemError.badStatusCode(code: response.status.code)
    }
  }

  public func resignID(_ id: ActorID) {
    self.lock.withLockVoid {
      log.trace("Resign id", metadata: [
        "actor/id": "\(id)"
      ])
      self.managed.removeValue(forKey: id)
    }
  }

  @TaskLocal
  private static var predefinedID: ActorID? = nil

  public func host<Act: DistributedActor>(
          _ type: Act.Type = Act.self,
          idleTimeout: Duration? = nil,
          factory: @escaping @Sendable () async -> Act
  ) throws where Act.ID == ActorID {
    let path = self.makePath(Act.self)
    try self.host(path, with: type, idleTimeout: idleTimeout, factory: factory)
  }

  public func host<Act: DistributedActor>(
          _ path: String,
          with type: Act.Type = Act.self,
          idleTimeout: Duration? = nil,
          factory: @escaping @Sendable () async -> Act) throws where Act.ID == ActorID {
    self.lock.lock()
    defer { self.lock.unlock() }

    self.log.notice("Registered oh-demand handler for path [\(path)]", metadata: [
      "rootPath": "\(path)",
      "actor/type": "\(Act.self)",
    ])

    self.onDemandFactories[path] = { id in
      await HTTPActorSystem.$predefinedID.withValue(id) {
        await factory()
      }
    }
  }

  private func makePath<Act: DistributedActor>(_ actType: Act.Type) -> String {
    let fqn = "\(Act.self)"
    return (fqn.split(separator: ".").last.map { String($0) }) ?? fqn
  }

  func sendEnvelopeRequest(_ invocation: InvocationEncoder,
                           target: RemoteCallTarget,
                           to recipient: ActorID) async throws -> HTTPClient.Response {
    // try await InstrumentationSystem.tracer.withSpan(message.functionIdentifier) { span in
    let callID = UUID()
    // Prepare the message envelope
    let envelope: RemoteCallEnvelope =
            try invocation.makeEnvelope(
                    recipient: recipient,
                    target: target,
                    callID: callID)

//        // inject metadata values to propagate for distributed tracing
//        if let baggage = Baggage.current {
//            InstrumentationSystem.instrument.inject(baggage, into: &envelope.metadata, using: MessageEnvelopeMetadataInjector())
//        }

    let requestData = try invocation.encoder.encode(envelope)
    log.debug("Send request to \(recipient.uri)", metadata: [
      "envelope": "\(String(data: requestData, encoding: .utf8)!)",
      "recipient": "\(recipient.uri)"
    ])

    let response = try await sendHTTPRequest(requestURI: recipient.uri, target: target, requestData: requestData)
    log.debug("Received response \(response)", metadata: [
      "response/payload": "\(response.body?.getString(at: 0, length: response.body?.readableBytes ?? 0) ?? "")"
    ])

    return response
    // }
  }


  private func sendHTTPRequest(requestURI: String, target: RemoteCallTarget, requestData: Data) async throws -> HTTPClient.Response {
    // try await InstrumentationSystem.tracer.withSpan("HTTP POST", ofKind: .client) { span in
    let url: String
    if let simpleMethodName = target.methodBaseName {
      url = "\(requestURI)/\(simpleMethodName)"
    } else {
      url = requestURI
    }
    let request = try HTTPClient.Request(
            url: url,
            method: .POST,
            headers: [
              "Content-Type": "application/json"
            ],
            body: .data(requestData))
    // span.attributes["http.method"] = "POST"
    // span.attributes["http.url"] = requestURI

    let future = client.execute(
            request: request,
            deadline: .now() + .seconds(3)) // A real implementation would allow configuring these (i.e. pick up a task-local deadline)

    let response = try await future.get()
    // span.attributes["http.status_code"] = Int(response.status.code)
    return response
    // }
  }

  public func makeInvocationEncoder() -> InvocationEncoder {
    let encoder = JSONEncoder()
    encoder.userInfo[.actorSystemKey] = self

    return InvocationEncoder(encoder: encoder)
  }

  /// Actually deliver the message to the local recipient
  func deliver(envelope: RemoteCallEnvelope, promise replyPromise: EventLoopPromise<Data>) async {
    log.info("Attempt delivery to \(envelope.recipient) and envelope=[\(envelope.target) - \(envelope.targetIdentifier)]")

    var resolved = lock.withLock {
      self.managed[envelope.recipient]
    }

    // No specific actor resolved, we can attempt to resolve ad-hoc if there was a host() call made for this type of actor before.
    if resolved == nil {
      resolved = await self.resolveOnDemand(for: envelope)
      if let resolved {
        log.debug("Resolve on-demand succeeded, allocated new actor: \(resolved.id)", metadata: [
          "actor/id": "\(resolved.id)",
          "actor/type": "\(type(of: resolved))",
        ])
      }
    }

    guard let known = resolved else {
      log.warning("No actor found to deliver to", metadata: [
        "actor/id": "\(envelope.recipient)"
      ])
      replyPromise.fail(HTTPActorSystemError.actorNotFound(envelope.recipient))
      return
    }

    log.debug("Delivering to local instance: \(known)", metadata: [
      "actor/id": "\(known)",
      "target": "\(envelope.target)",
    ])

    let decoder = JSONDecoder()
    decoder.userInfo[.actorSystemKey] = self
    var invocationDecoder = HTTPInvocationDecoder(decoder: decoder, envelope: envelope)

    let resultHandler = HTTPInvocationResultHandler(
            system: self,
            callID: envelope.callID,
            replyPromise: replyPromise
    )

    do {
      try await self.executeDistributedTarget(
              on: known,
              target: envelope.target,
              invocationDecoder: &invocationDecoder,
              handler: resultHandler
      )
    } catch {
      fatalError("Failed to deliver: \(error)")
    }
  }

  private func resolveOnDemand(for envelope: RemoteCallEnvelope) async -> (any DistributedActor)? {
    let actorPath = envelope.recipient.path
    let factory = self.lock.withLock {
      self.onDemandFactories[actorPath]
    }
    guard let factory else {
      return nil
    }
    return await factory(envelope.recipient)
  }

  public func shutdown() async throws {
    self.lock.lock()
    defer { self.lock.unlock() }

    if let client = self.client {
      try await client.shutdown().get()
    }
    if let server = self.server {
      try await server.channel.close()
      try await server.group.shutdownGracefully()
    }
  }
}

extension RemoteCallTarget {
  var methodBaseName: String? {
    guard let part = description.split(separator: "(").first else {
      return nil
    }

    return part.split(separator: ".").last.map { String($0) }
  }
}

public struct HTTPInvocationDecoder: DistributedTargetInvocationDecoder {
  public typealias SerializationRequirement = Codable

  let decoder: JSONDecoder
  let envelope: RemoteCallEnvelope
  var argIndex = 0

  public init(decoder: JSONDecoder, envelope: RemoteCallEnvelope) {
    self.decoder = decoder
    self.envelope = envelope
  }

  public mutating func decodeGenericSubstitutions() throws -> [Any.Type] {
    [] // generics not supported in this sample impl
  }

  public mutating func decodeNextArgument<Argument: SerializationRequirement>() throws -> Argument {
    guard envelope.arguments.count > argIndex else {
      throw HTTPActorSystemError.unexpectedNumberOfArguments(known: envelope.arguments.count, required: argIndex + 1)
    }
    let data = envelope.arguments[argIndex]
    argIndex += 1
    return try self.decoder.decode(Argument.self, from: data)
  }

  public mutating func decodeErrorType() throws -> Any.Type? {
    nil // not necessary to encode in this impl
  }

  public mutating func decodeReturnType() throws -> Any.Type? {
    nil // not necessary to encode in this impl
  }
}

extension HTTPActorSystem {
  public struct ActorID: Sendable, Codable, Hashable, CustomStringConvertible {
    public var `protocol`: String
    public var host: String
    public var port: Int
    public var path: String
    public var uuid: UUID

    public init(host: String, port: Int, path: String, uuid: UUID) {
      self.`protocol` = "http"
      self.host = host
      self.port = port
      self.path = path
      self.uuid = uuid
    }

    var uri: String {
      "\(`protocol`)://\(host):\(port)/\(path)/\(uuid)"
    }

    public var description: String {
      "\(path)#\(uuid)"
    }
  }
}

public struct HTTPInvocationEncoder: DistributedTargetInvocationEncoder {
  public typealias SerializationRequirement = Codable

  var genericSubstitutions: [String] = []
  var arguments: [Data] = []
  var throwing: Bool = false

  let encoder: JSONEncoder

  /// This serialization mode is a bit simplistic, but good enough for our sample
  public init(encoder: JSONEncoder) {
    self.encoder = encoder
  }

  public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {
    fatalError("The \(Self.self) sample implementation does not support generics (but could)")
  }

  public mutating func recordArgument<Value: Codable>(_ argument: RemoteCallArgument<Value>) throws {
    let encoded = try encoder.encode(argument.value)
    self.arguments.append(encoded)
  }

  public mutating func recordErrorType<E: Error>(_ type: E.Type) throws {
    self.throwing = true // we don't record specific error type in this impl
  }

  public mutating func recordReturnType<R: SerializationRequirement>(_ type: R.Type) throws {
    // ignore
  }

  public mutating func doneRecording() throws {
    // ignore
  }

  func makeEnvelope(recipient: HTTPActorSystem.ActorID,
                    target: RemoteCallTarget,
                    callID: HTTPActorSystem.CallID) throws -> RemoteCallEnvelope {
    try RemoteCallEnvelope(
            recipient: recipient,
            target: target.identifier,
            callID: callID,
            arguments: arguments)
  }
}

public struct HTTPInvocationResultHandler: DistributedTargetInvocationResultHandler {
  public typealias SerializationRequirement = Codable

  let callID: HTTPActorSystem.CallID
  let system: HTTPActorSystem
  let replyPromise: EventLoopPromise<Data>

  public init(system: HTTPActorSystem,
              callID: HTTPActorSystem.CallID,
              replyPromise: EventLoopPromise<Data>) {
    self.system = system
    self.callID = callID
    self.replyPromise = replyPromise
  }

  public func onReturnVoid() async throws {
    system.log.trace("onReturnVoid", metadata: ["callID": "\(callID)"])
    let encoder = JSONEncoder()
    encoder.userInfo[.actorSystemKey] = system

    do {
      let data = try encoder.encode(_Done())
      replyPromise.succeed(data)
    } catch {
      replyPromise.fail(error)
    }
  }

  public func onReturn<Success: Codable>(value: Success) async throws {
    system.log.trace("onReturn: \(value)", metadata: ["callID": "\(callID)"])

    let encoder = JSONEncoder()
    encoder.userInfo[.actorSystemKey] = system

    do {
      let data = try encoder.encode(value)
      replyPromise.succeed(data)
    } catch {
      replyPromise.fail(error)
    }
  }

  public func onThrow<Err: Error>(error: Err) async throws {
    fatalError("onThrow - not implemented yet: \(error)")
  }
}

public struct RemoteCallEnvelope: Sendable, Codable {
  public let recipient: HTTPActorSystem.ActorID
  public let targetIdentifier: String
  /// Specific UUID for this call. Not strictly necessary in a HTTP implementation where we request/reply already,
  /// but generally used in other kinds of systems to be able to reply "later".
  public let callID: UUID
  public let arguments: [Data]
  public var metadata: [String: String]

  public var target: RemoteCallTarget {
    .init(self.targetIdentifier)
  }

  // Naive implementation, encodes the `message` as bytes blob using the `encoder`.
  init(recipient: HTTPActorSystem.ActorID,
       target targetIdentifier: String,
       callID: UUID,
       arguments: [Data]) throws {
    self.recipient = recipient
    self.targetIdentifier = targetIdentifier
    self.callID = callID
    self.arguments = arguments
    self.metadata = [:]
  }
}

public struct _Done: Codable {}

public struct RemoteCallReply<Value: Codable>: Encodable, Decodable {
  typealias CallID = HTTPActorSystem.CallID

  let callID: CallID
  let value: Value?

  init(callID: CallID, value: Value) {
    self.callID = callID
    self.value = value
  }

  init<Err: Error>(callID: CallID, error: Err) {
    fatalError("Error reply not implemented yet")
  }

  enum CodingKeys: String, CodingKey {
    case callID = "cid"
    case value = "v"
    case wasThrow = "t"
    case thrownError = "e"
    case thrownErrorManifest = "em"
  }

  public init(from decoder: Decoder) throws {
//        guard let context = decoder.actorSerializationContext else {
//            throw SerializationError.missingSerializationContext(decoder, Self.self)
//        }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.callID = try container.decode(CallID.self, forKey: .callID)

//        let wasThrow = try container.decodeIfPresent(Bool.self, forKey: .wasThrow) ?? false
//        if wasThrow {
//            let errorManifest = try container.decode(Serialization.Manifest.self, forKey: .thrownErrorManifest)
//            let summonedErrorType = try context.serialization.summonType(from: errorManifest)
//            guard let errorAnyType = summonedErrorType as? (Error & Codable).Type else {
//                throw SerializationError(.notAbleToDeserialize(hint: "manifest type results in [\(summonedErrorType)] type, which is NOT \((Error & Codable).self)"))
//            }
//            self.thrownError = try container.decode(errorAnyType, forKey: .thrownError)
//            self.value = nil
//        } else {
    self.value = try container.decode(Value.self, forKey: .value)
    // self.thrownError = nil
//        }
  }

  public func encode(to encoder: Encoder) throws {
//        guard let context = encoder.actorSerializationContext else {
//            throw SerializationError.missingSerializationContext(encoder, Self.self)
//        }

    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(self.callID, forKey: .callID)

    // TODO: error handling
//        if let thrownError = self.thrownError {
//            try container.encode(true, forKey: .wasThrow)
//            let errorManifest = try context.serialization.outboundManifest(type(of: thrownError))
//            try container.encode(thrownError, forKey: .thrownError)
//            try container.encode(errorManifest, forKey: .thrownErrorManifest)
//        } else {
    if let value = self.value {
      try container.encode(value, forKey: .value)
    }
//        }
  }

}

enum HTTPActorSystemError: DistributedActorSystemError {
  // Resolve errors
  case actorNotFound(HTTPActorSystem.ActorID)

  // Invocation decoding errors
  case unexpectedNumberOfArguments(known: Int, required: Int)

  // Response errors
  case unableToDecodeResponse(body: ByteBuffer, expectedType: Any.Type, error: Error)
  case missingResponsePayload(expected: Any.Type)
  case badStatusCode(code: UInt)
}
