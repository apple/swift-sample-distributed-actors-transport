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

import XCTest
@testable import FishyActorsDemo

final class ChatRoomTest: XCTestCase {

  func test_ChatRoom_shouldAllowJoining() async {
    let transport = TestTransport()

    let room = ChatRoom(topic: "Test", transport: transport)
    let chatter = Chatter(transport: transport)

    try! await room.join(chatter: chatter)
  }

}