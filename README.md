# swift-sample-distributed-actors-transport

Sample application and `ActorTransport`, associated with `distributed actor` language evolution proposal.

## Running the sample app

1. Download the latest toolchain from `main` branch, or a built one from a specific PR. 

2. Move it to `Library/Developer/Toolchains/` and point the TOOLCHAIN env variable at it:

```
export TOOLCHAIN=/Library/Developer/Toolchains/swift-PR-39019-1091.xctoolchain
```

To run the sample app, use the following command:

```
DYLD_LIBRARY_PATH=$TOOLCHAIN/usr/lib/swift/macosx $TOOLCHAIN/usr/bin/swift run 
```

all necessary flags to build this pre-release feature are already enabled as unsafe flags in `Package.swift`.

If you wanted to perform the invocation manually, it would look something like this:

```
DYLD_LIBRARY_PATH=$TOOLCHAIN/usr/lib/swift/macosx $TOOLCHAIN/usr/bin/swift run -c debug -Xswiftc -Xfrontend -Xswiftc -validate-tbd-against-ir=none -Xswiftc -target -Xswiftc x86_64-apple-macos12.0 -Xswiftc -Xfrontend -Xswiftc -enable-experimental-distributed
```

setting the `DYLD_LIBRARY_PATH` is important, so don't forget it.

Notice we're also passing the `-frontend -enable-experimental-distributed` flag. The same flag is already preconfigured in SwiftPM settings, however this is another way to pass it explicitly, if you'd like to play around in existing projects or command line.
