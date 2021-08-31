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

import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
import struct Foundation.Data
import NIO
import NIOFoundationCompat

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Encoding

// TODO(swift): should be lifted into stdlib; in order to not depend on Combine
public protocol TopLevelEncoder: Sendable {
  associatedtype Output: Sendable
  func encode<T>(_ value: T) throws -> Output where T : Encodable
}

extension JSONEncoder: @unchecked Sendable, TopLevelEncoder {
  typealias Input = Data
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Decoding

// TODO(swift): should be lifted into stdlib; in order to not depend on Combine
public protocol TopLevelDecoder: Sendable {
  associatedtype Input
  func decode<T>(_ type: T.Type, from data: Input) throws -> T where T : Decodable
}

extension JSONDecoder: @unchecked Sendable, TopLevelDecoder {
  typealias Output = Data
}

// This is a hack
extension Data: @unchecked Sendable {}