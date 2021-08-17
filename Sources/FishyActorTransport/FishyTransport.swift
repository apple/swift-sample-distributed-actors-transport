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
import NIO
import AsyncHTTPClient

@available(macOS 12.0, *)
public final class FishyTransport: ActorTransport {
    let host: String
    let port: Int
    
    public init(host: String, port: Int){
        self.host = host
        self.port = port
    }
    
    public func decodeIdentity(from decoder: Decoder) throws -> AnyActorIdentity {
        let container = try decoder.container(keyedBy: Envelope.CodingKeys.self)
        let sender = try container.decode(String.self, forKey: Envelope.CodingKeys.sender)
        
        // TODO: validate if it actually is a FishyIdentity etc.
        let id = FishyIdentity(id: sender)

        return AnyActorIdentity(id)
    }
    
    public func resolve<Act>(_ identity: AnyActorIdentity, as actorType: Act.Type) throws -> ActorResolved<Act> where Act : DistributedActor {
        fatalError(#function)
    }
    
    public func assignIdentity<Act>(_ actorType: Act.Type) -> AnyActorIdentity where Act : DistributedActor {
        fatalError(#function)
    }
    
    public func actorReady<Act>(_ actor: Act) where Act : DistributedActor {
        fatalError(#function)
    }
    
    public func resignIdentity(_ id: AnyActorIdentity) {
        fatalError(#function)
    }
    
}

public struct FishyIdentity: ActorIdentity {
    let id: String
    
}

@available(macOS 12.0, *)
public struct Envelope: Codable {
    enum CodingKeys: CodingKey {
        case sender
        case message
        case metadata
    }
    
    let sender: String
    let message: String
    let metadata: [String: String]
}
