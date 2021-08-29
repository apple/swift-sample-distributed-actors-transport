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

import SwiftSyntax
import Foundation

final class Analysis: SyntaxVisitor {

  private let sourceDirectory: String
  private let verbose: Bool

  var decls: [DistributedActorDecl] = []
  private var currentDecl: DistributedActorDecl? = nil

  init(sourceDirectory: String, verbose: Bool) {
    self.sourceDirectory = sourceDirectory
    self.verbose = verbose
  }

  func run() {
    let enumerator = FileManager.default.enumerator(atPath: sourceDirectory)
    while let path = enumerator?.nextObject() as? String {
      guard path.hasSuffix(".swift") else {
        continue
      }

      let relativeURL = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: sourceDirectory))
      let url = relativeURL.absoluteURL
      do {
        try analyze(file: url)
      } catch {
        fatalError("ERROR: Failed analysis of [\(url)]: \(error)")
      }
    }
  }

  func analyze(file path: URL) throws {
    if verbose {
      print("Analyze: \(path)")
    }
    let sourceFile = try SyntaxParser.parse(path)
    self.walk(sourceFile)
  }

  // ==== ----------------------------------------------------------------------

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    guard isDistributedActor(node) else {
      return .skipChildren
    }

    if verbose {
      print("  Detected distributed actor: \(node.identifier.text)")
    }
    
    self.currentDecl = DistributedActorDecl(
        access: .internal,
        name: "\(node.identifier.text)",
        funcs: [] // TODO: just a mock impl
    )

    return .visitChildren
  }

  override func visitPost(_ node: ClassDeclSyntax) {
    if let decl = currentDecl {
      decls.append(decl)
      currentDecl = nil
    }
  }

  func isDistributedActor(_ node: ClassDeclSyntax) -> Bool {
    let isActor = node.classOrActorKeyword.text == "actor"
    guard isActor else {
      return false
    }
    
    guard let mods = node.modifiers else {
      return false
    }
    
    for mod in mods {
      if mod.name.text ==  "distributed" {
        return true
      }
    }
    
    return false
  }
}

struct DistributedActorDecl {
  let access: AccessControl
  let name: String
  let funcs: [FuncDecl]
}

enum AccessControl: String {
  case `public`
  case `internal`
  case `private`
}

struct FuncDecl {
  let name: String
  let params: [(String, String)]
  let result: String
}

