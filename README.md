# swift-sample-distributed-actors-transport

Sample application and `ActorTransport`, associated with `distributed actor` language evolution proposal.

## Running the sample app

1. Download the latest toolchain from `main` branch, or a built one from a specific PR. (Alternatively [swift-PR-39087-1111-osx.tar.gz](https://ci.swift.org/job/swift-PR-toolchain-osx/1111//artifact/branch-main/swift-PR-39087-1111-osx.tar.gz), if still available, is a fine toolchain to use for this sample app.)

3. Move it to `Library/Developer/Toolchains/` and point the TOOLCHAIN env variable at it:

```
export TOOLCHAIN=/Library/Developer/Toolchains/swift-PR-39061-1098.xctoolchain
```

To run the sample app, use the following command:

```
cd SampleApp
DYLD_LIBRARY_PATH=$TOOLCHAIN/usr/lib/swift/macosx $TOOLCHAIN/usr/bin/swift run FishyActorsDemo
```

all necessary flags to build this pre-release feature are already enabled as unsafe flags in `Package.swift`.

If you wanted to perform the invocation manually, it would look something like this:

```
export TOOLCHAIN=/Library/Developer/Toolchains/swift-PR-39087-1109.xctoolchain
DYLD_LIBRARY_PATH=$TOOLCHAIN/usr/lib/swift/macosx $TOOLCHAIN/usr/bin/swift run FishyActorsDemo
```

setting the `DYLD_LIBRARY_PATH` is important, so don't forget it.

### Experimental flags

> This project showcases **EXPERIMENTAL** language features, and in order to access them the `-enable-experimental-distributed` flag must be set.

The project is pre-configured with a few experimental flags that are necessary to enable distributed actors, these are configured in each target's `swiftSettings`:

```swift
      .target(
          name: "FishyActorTransport",
          dependencies: [
            ...
          ],
          swiftSettings: [
            .unsafeFlags([
              "-Xfrontend", "-enable-experimental-distributed",
              "-Xfrontend", "-validate-tbd-against-ir=none",
              "-Xfrontend", "-disable-availability-checking", // availability does not matter since _Distributed is not part of the SDK at this point
            ])
          ]),
```

## SwiftPM Plugin

Distributed actor transports are expected to ship with an associated SwiftPM plugin that takes care of source generating the necessary "glue" between distributed functions and the transport runtime.

Plugins are run automatically when the project is build, and therefore add no hassle to working with distributed actors.

### Verbose mode

It is possible to force the plugin to run in `--verbose` mode by setting the `VERBOSE` environment variable, like this:


```
VERBOSE=true DYLD_LIBRARY_PATH=$TOOLCHAIN/usr/lib/swift/macosx $TOOLCHAIN/usr/bin/swift run FishyActorsDemo
       ^
/Users/ktoso/code/fishy-actor-transport/Package.swift:68:67: warning: 'branch' is deprecated
      .package(url: "https://github.com/apple/swift-syntax.git", .branch("main")) // FIXME: needs better versioned tags
                                                                  ^
Analyze: file:///Users/ktoso/code/fishy-actor-transport/Sources/FishyActorsDemo/_PrettyDemoLogger.swift
Analyze: file:///Users/ktoso/code/fishy-actor-transport/Sources/FishyActorsDemo/Actors.swift
  Detected distributed actor: ChatRoom
Analyze: file:///Users/ktoso/code/fishy-actor-transport/Sources/FishyActorsDemo/main.swift
Generate extensions...
  Generate 'FishyActorTransport' extensions for 'distributed actor ChatRoom' -> file:///Users/ktoso/code/fishy-actor-transport/.build/plugins/outputs/fishy-actor-transport/FishyActorsDemo/FishyActorTransportPlugin/GeneratedFishyActors_1.swift
```
