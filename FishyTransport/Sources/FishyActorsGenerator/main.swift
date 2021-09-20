//===----------------------------------------------------------------------===//
//
// This source file is part of the fishy-actor-transport open source project
//
// Copyright (c) 2021 Apple Inc. and the fishy-actor-transport project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of fishy-actor-transport project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import ArgumentParser

// very naive pretty printing
let Bold = "\u{001B}[0;1m"
let Reset = "\u{001B}[0;0m"

struct FishyActorsGeneratorMain: ParsableCommand {
  @Flag(help: "Print verbose logs")
  var verbose: Bool = false

  @Option(help: "'Sources/' directory")
  var sourceDirectory: String

  @Option(help: "Target directory for generated sources")
  var targetDirectory: String

  @Option(help: "How many files to spread the generated files into")
  var buckets: Int = 1

  mutating func run() throws {
    // Step 1: Analyze all files looking for `distributed actor` decls
    let analysis = Analysis(sourceDirectory: sourceDirectory, verbose: verbose)
    analysis.run()

    // Optimization: If nothing changed since our last run, just return

    // Step 2: Source generate necessary bits for every decl
    if verbose {
      print("Generate extensions...")
    }

    let sourceGen = SourceGen(buckets: buckets)
    
    for decl in analysis.decls {
      if verbose {
        print("  Generate 'FishyActorTransport' extensions for 'distributed actor \(decl.name)' -> \(targetFilePath(targetDirectory: targetDirectory, i: 1))")
      }
      
      let source = try sourceGen.generate(decl: decl)
      let filePath = targetFilePath(targetDirectory: targetDirectory, i: source.bucket)
      
      try source.text.write(to: filePath, atomically: true, encoding: .utf8)
    }
  }
}

func targetFilePath(targetDirectory: String, i: Int) -> URL {
  URL(fileURLWithPath: "\(targetDirectory)/GeneratedFishyActors_\(i).swift")
}

if #available(macOS 12.0, /* Linux */ *) {
  FishyActorsGeneratorMain.main()
} else {
  fatalError("Unsupported platform")
}
