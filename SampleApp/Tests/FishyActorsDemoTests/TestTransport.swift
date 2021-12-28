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

// TODO: such test transport can implement intercepting messages, and storing them for future checks etc
final class TestTransport: ActorTransport {

  struct Identity: ActorIdentity {
    let id: Int
  }

  func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act? where Act: DistributedActor {
    fatalError("resolve(_:as:) has not been implemented")
  }

  func assignID<Act>(_ actorType: Act.Type) -> ActorID where Act: DistributedActor {
    return .init(Identity(id: .random(in: 1...Int.max)))
  }

  func actorReady<Act>(_ actor: Act) where Act: DistributedActor {
  }

  func resignID(_ id: ActorID) {
  }
}