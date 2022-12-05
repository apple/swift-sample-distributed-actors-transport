# swift-sample-distributed-actors-transport

Sample application showcasing a simplistic `DistributedActorSystem` implementation, associated with `distributed actor` language evolution proposal.

## Running the sample app

> Note: Distributed actors are part of Swift since Swift 5.7, so make sure you are using a recent-enough Swift to run this sample.

To run the sample app, use the following command:

```
cd SampleApp
swift run FishyActorsDemo 
```

If you wanted to perform the invocation manually, it would look something like this:

### The sample `DistributedActorSystem` implementation

This project includes a sample implementation of the [`DistributedActorSystem`](https://developer.apple.com/documentation/distributed/distributedactorsystem),
that ships in the `Distributed` module along with Swift 5.7+. A distributed actor system is what enables actors to be declared as `distributed actor`, and 
make calls to them across process boundaries.

The underlying transport is independent of the language feature that defines the `distributed actor` and related types, and can be implemented by end-users.
One such example implementation is the `HTTPActorSystem` in this sample, which attempts a _very simplistic_ but relatively simple to follow implementation approach.

For a more advanced and feature rich implementation of a distributed actor system, designed for high performance distributed clusters for use in data centers
please refer to the `DistributedCluster` located here: https://github.com/apple/swift-distributed-actors/

We also recommend viewing the WWDC 2022 talk introducing the distributed actors language feature: **[WWDC 2022: Meet distributed actors in Swift](https://developer.apple.com/videos/play/wwdc2022/110356/)**.

### Sample output

The sample is a chat room application. It creates a few "nodes" and starts distributed actors on them. 

There are two kinds of actors, a `ChatRoom` and `Chatter`s. A single node, representing a cloud component, hosts the chat room. And a few other nodes host chatters. Note that chatters can be on the same or on different nodes.

As the application runs, chatters join the remote `ChatRoom` and say hello there.

The chat room logs whenever a chatter joins the room, or sends a message:

```
// chat room logs
[:8001/ChatRoom@130A3D1B-...] Chatter [:9003/Chatter@0A2F138C-...] joined this chat room about: 'Cute Capybaras'
[:8001/ChatRoom@130A3D1B-...] Chatter [:9002/Chatter@8152F16D-...] joined this chat room about: 'Cute Capybaras'
[:8001/ChatRoom@130A3D1B-...] Chatter [:9003/Chatter@4F3970DE-...] joined this chat room about: 'Cute Capybaras'
[:8001/ChatRoom@130A3D1B-...] Forwarding message from [:9002/Chatter@8152F16D-...] to 2 other chatters...
[:8001/ChatRoom@130A3D1B-...] Forwarding message from [:9003/Chatter@4F3970DE-...] to 2 other chatters...
[:8001/ChatRoom@130A3D1B-...] Forwarding message from [:9003/Chatter@0A2F138C-...] to 2 other chatters...
[:8001/ChatRoom@130A3D1B-...] Forwarding message from [:9002/Chatter@8152F16D-...] to 2 other chatters...
[:8001/ChatRoom@130A3D1B-...] Forwarding message from [:9003/Chatter@4F3970DE-...] to 2 other chatters...
```

The chat room sends a `"Welcome ..."` message to a joining chatter, and forwards all other chat messages sent to the room to the chatter itself.
A chatters logs look like this: 

```
// first chatter
[:9002/Chatter@8152F16D-...] Welcome to the 'Cute Capybaras' chat room! (chatters: 2)
[:9002/Chatter@8152F16D-...] Chatter [:9003/Chatter@0A2F138C-...] joined [:8001/ChatRoom@130A3D1B-...] (total known members in room 2 (including self))
[:9002/Chatter@8152F16D-...]] :9003/Chatter@4F3970DE-... wrote: Welcome [:9003/Chatter@0A2F138C-...]!
[:9002/Chatter@8152F16D-...]] :9003/Chatter@0A2F138C-... wrote: Long time no see [:9002/Chatter@8152F16D-...]!
[:9002/Chatter@8152F16D-...] Chatter [:9003/Chatter@4F3970DE-...] joined [:8001/ChatRoom@130A3D1B-...] (total known members in room 3 (including self))
[:9002/Chatter@8152F16D-...]] :9003/Chatter@4F3970DE-... wrote: Hi there,  [:9002/Chatter@8152F16D-...]!
```

Notice that the simplified ID printout contains the port number of the node the chatter is running on. In this example, the chatroom is running on port `8001` while the chatter is on `9002`. Other chatters may be on the same or on different "nodes" which are represented by actor transport instances. 

This sample is a distributed application created from just a single process, but all the "nodes" communicate through networking with eachother.
The same application could be launched on different physical hosts (and then would have different IP addresses), this is what location transparency of distributed actors enables us to do.

