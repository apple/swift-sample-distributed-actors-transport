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

import PackagePlugin

@main struct MyPlugin: BuildToolPlugin {

  func createBuildCommands(context: TargetBuildContext) throws -> [Command] {
    let toolName = "FishyActorsGenerator"
    let genTool = try context.tool(named: toolName)
    let generatorPath = try context.tool(named: toolName).path

    let inputFiles = context.inputFiles
        .map { $0.path }
        .filter { $0.extension?.lowercased() == "swift" }

    let buckets = 5 // # of buckets for consistent hashing
    let outputFiles = !inputFiles.isEmpty ? (0..<buckets)
        .map {
      context.pluginWorkDirectory.appending("GeneratedFishyActors_\($0).swift")
    } : []

    let command = Command.buildCommand(
        displayName: "Distributed Actors: Generating FISHY actors for \(context.targetName)",
        executable: generatorPath,
        arguments: [
          "--verbose",
          "--source-directory", context.targetDirectory.string,
          "--target-directory", context.pluginWorkDirectory.string,
          "--buckets", "\(buckets)",
        ],
        inputFiles: inputFiles,
        outputFiles: outputFiles
    )

    return [command]
  }
}