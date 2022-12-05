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
import ArgumentParser
import Logging
import Foundation

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Support

// Make logger level codable to use it as option in the Argument Parser main struct.
extension Logger.Level: EnumerableFlag {}

extension DistributedActor where ActorSystem == HTTPActorSystem  {
    nonisolated var description: String {
        "\(Self.self)(\(self.id))"
    }
}
