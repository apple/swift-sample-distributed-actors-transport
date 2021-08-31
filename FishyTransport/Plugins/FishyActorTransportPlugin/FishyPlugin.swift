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

import PackagePlugin

let toolName = "FishyActorsGenerator"
let genTool = try targetBuildContext.tool(named: toolName)
let generatorPath = try targetBuildContext.tool(named: toolName).path

let inputFiles = targetBuildContext.inputFiles
    .map { $0.path }
    .filter { $0.extension?.lowercased() == "swift" }

let buckets = 5 // # of buckets for consistent hashing
let outputFiles = !inputFiles.isEmpty ? (0 ..< buckets)
    .map { targetBuildContext.pluginWorkDirectory.appending("GeneratedFishyActors_\($0).swift") } : []

commandConstructor.addBuildCommand(
    displayName: "Distributed Actors: Generating FISHY actors for \(targetBuildContext.targetName)",
    executable: generatorPath,
    arguments: [
      "--verbose",
      "--source-directory", targetBuildContext.targetDirectory.string,
      "--target-directory", targetBuildContext.pluginWorkDirectory.string,
      "--buckets", "\(buckets)",
    ],
    inputFiles: inputFiles,
    outputFiles: outputFiles
)