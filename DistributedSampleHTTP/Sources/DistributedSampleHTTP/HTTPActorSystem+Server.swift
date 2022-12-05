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
import NIO
import NIOHTTP1
import Foundation

private final class HTTPHandler: @unchecked Sendable, ChannelInboundHandler, RemovableChannelHandler {
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundOut = HTTPServerResponsePart

  private let system: HTTPActorSystem

  private var messageBytes: ByteBuffer = ByteBuffer()
  private var messageRecipientURI: String = ""
  private var state: State = .idle
  private enum State {
    case idle
    case waitingForRequestBody
    case sendingResponse

    mutating func requestReceived() {
      precondition(self == .idle, "Invalid state for request received: \(self)")
      self = .waitingForRequestBody
    }

    mutating func requestComplete() {
      precondition(self == .waitingForRequestBody, "Invalid state for request complete: \(self)")
      self = .sendingResponse
    }

    mutating func responseComplete() {
      precondition(self == .sendingResponse, "Invalid state for response complete: \(self)")
      self = .idle
    }
  }

  init(system: HTTPActorSystem) {
    self.system = system
  }

  func handlerAdded(context: ChannelHandlerContext) {
  }

  func handlerRemoved(context: ChannelHandlerContext) {
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch unwrapInboundIn(data) {
    case .head(let head):
      if self.isHealthCheck(head) {
        self.respondHealthCheck(context: context)
        return
      }

      guard case .POST = head.method else {
        self.respond405(context: context)
        return
      }

      system.log.info("Received [\(head.method) \(head.uri)]")

      messageRecipientURI = head.uri
      state.requestReceived()

    case .body(var bytes):
      if (state == State.idle) { return }
      messageBytes.writeBuffer(&bytes)

    case .end:
      if (state == State.idle) { return }
      onMessageComplete(context: context, messageBytes: messageBytes)
      state.requestComplete()
      messageBytes.clear()
      messageRecipientURI = ""
    }
  }

  func onMessageComplete(context: ChannelHandlerContext, messageBytes: ByteBuffer) {
    let decoder = JSONDecoder()
    decoder.userInfo[.actorSystemKey] = system

    let envelope: RemoteCallEnvelope
    do {
      envelope = try decoder.decode(RemoteCallEnvelope.self, from: messageBytes)
    } catch {
      self.system.log.error("Failed to decode \(RemoteCallEnvelope.self)", metadata: [
        "error": "\(error)",
      ])
      self.respond500(context: context, error: error)
      return
    }
    let promise = context.eventLoop.makePromise(of: Data.self)
    Task {
      await self.system.deliver(envelope: envelope, promise: promise)
    }
    promise.futureResult.whenComplete { result in
      var headers = HTTPHeaders()
      headers.add(name: "Content-Type", value: "application/json")

      let responseHead: HTTPResponseHead
      let responseBody: ByteBuffer
      switch result {
      case .failure(let error):
        let status: HTTPResponseStatus
        let errorString: String
        if let error = error as? HTTPActorSystemError {
          switch error {
          case .actorNotFound:
            status = .notFound
            errorString = "{\"error\"=\"not-found\"}"
          default:
            status = .internalServerError
            errorString = "{\"error\"=\"\(type(of: error))\"}"
          }
        } else {
          status = .internalServerError
          errorString = "{\"error\"=\"\(type(of: error))\"}"
        }

        responseHead = HTTPResponseHead(version: .init(major: 1, minor: 1),
                status: status,
                headers: headers)
        responseBody = ByteBuffer(string: errorString)
      case .success(let data):
        responseHead = HTTPResponseHead(version: .init(major: 1, minor: 1),
                status: .ok,
                headers: headers)
        responseBody = ByteBuffer(data: data)
      }
      headers.add(name: "Content-Length", value: String(responseBody.readableBytes))
      headers.add(name: "Connection", value: "close")
      context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
      context.write(self.wrapOutboundOut(.body(.byteBuffer(responseBody))), promise: nil)
      context.write(self.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<Void, Error>) in
        context.close(promise: nil)
      }
      context.flush()
    }
  }

  private func isHealthCheck(_ head: HTTPRequestHead) -> Bool {
    head.method == .GET && head.uri == "/__health"
  }

  private func respondHealthCheck(context: ChannelHandlerContext) {
    let headers = HTTPHeaders()
    let head = HTTPResponseHead(version: .http1_1,
            status: .ok,
            headers: headers)
    context.write(self.wrapOutboundOut(.head(head)), promise: nil)
    context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
    context.flush()
  }

  private func respond405(context: ChannelHandlerContext) {
    var headers = HTTPHeaders()
    headers.add(name: "Connection", value: "close")
    headers.add(name: "Content-Length", value: "0")
    let head = HTTPResponseHead(version: .http1_1,
            status: .methodNotAllowed,
            headers: headers)
    context.write(self.wrapOutboundOut(.head(head)), promise: nil)
    context.write(self.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<Void, Error>) in
      context.close(promise: nil)
    }
    context.flush()
  }

  private func respond500(context: ChannelHandlerContext, error: Error) {
    var headers = HTTPHeaders()
    headers.add(name: "Connection", value: "close")
    headers.add(name: "Content-Length", value: "0")
    let head = HTTPResponseHead(version: .http1_1,
            status: .internalServerError,
            headers: headers)
    context.write(self.wrapOutboundOut(.head(head)), promise: nil)
    context.write(self.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<Void, Error>) in
      context.close(promise: nil)
    }
    context.flush()
  }
}

/// The HTTP server acting as a front to the actor system, it handles incoming health checks and http requests which are forwared as http messages to the actor system.
final class HTTPActorSystemServer {

  var group: EventLoopGroup
  let system: HTTPActorSystem

  var channel: Channel! = nil

  init(group: EventLoopGroup, system: HTTPActorSystem) {
    self.group = group
    self.system = system
  }

  func bootstrap(host: String, port: Int) throws {
    assert(channel == nil)

    let bootstrap = ServerBootstrap(group: group)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in
              let httpHandler = HTTPHandler(system: self.system)
              return channel.pipeline.configureHTTPServerPipeline().flatMap {
                channel.pipeline.addHandler(httpHandler)
              }
            }

            // Enable SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

    channel = try bootstrap.bind(host: host, port: port).wait()
    assert(channel.localAddress != nil, "localAddress was nil!")
  }
}
