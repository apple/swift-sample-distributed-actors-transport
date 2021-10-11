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

import SwiftSyntax
import SwiftSyntaxParser
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

  public func run() {
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
      print("Analyze: \(path.relativePath)")
    }
    let sourceFile = try SyntaxParser.parse(path)
    self.walk(sourceFile)
  }

  // ==== ----------------------------------------------------------------------

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    guard isDistributed(node) else {
      return .skipChildren
    }

    if verbose {
      print("  Detected distributed actor: \(Bold)\(node.identifier.text)\(Reset)")
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

  // ==== ----------------------------------------------------------------------

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    guard var actorDecl = self.currentDecl else {
      // skip any func declarations which are outside of distributed actor
      // those are illegal anyway and will fail to typecheck
      // TODO: extensions need more logic for detecting the currentDecl
      return .skipChildren
    }

    guard isDistributed(node) else {
      return .skipChildren
    }

    let isThrowing: Bool
    switch node.signature.throwsOrRethrowsKeyword?.tokenKind {
    case .throwsKeyword, .rethrowsKeyword:
      isThrowing = true
    default:
      isThrowing = false
    }

    let isAsync: Bool
    switch node.signature.throwsOrRethrowsKeyword?.tokenKind {
    case .throwsKeyword, .rethrowsKeyword:
      isAsync = true
    default:
      isAsync = false
    }

    let resultTypeNaive: String
    if let t = node.signature.output?.returnType {
      resultTypeNaive = "\(t.withoutTrivia())"
    } else {
      // pretty naive representation, prefer an enum
      resultTypeNaive = "Void"
    }

    // TODO: this is just a naive implementation, we'd carry all information here
    let fun = FuncDecl(
      access: .internal,
      name: node.identifier.withoutTrivia().text,
      params: node.signature.gatherParams(),
      throwing: isThrowing,
      async: isAsync,
      result: resultTypeNaive
    )
    actorDecl.funcs.append(fun)

    if verbose {
      print("    Detected distributed func: \(Bold)\(fun.name)\(Reset)")
    }

    currentDecl = actorDecl
    return .skipChildren
  }

  // ==== ----------------------------------------------------------------------

  func isDistributed(_ node: ClassDeclSyntax) -> Bool {
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

  func isDistributed(_ node: FunctionDeclSyntax) -> Bool {
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

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Helpers

final class GatherParameters: SyntaxVisitor {
  typealias Output = [(String?, String, String)]
  var params: Output = []

  override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
    let firstName = node.firstName?.text
    guard let secondName = node.secondName?.text ?? firstName else {
      fatalError("No `secondName` or `firstName` available at: \(node)")
    }
    guard let type = node.type?.description else {
      fatalError("No `type` available at function parameter: \(node)")
    }

    self.params.append((firstName, secondName, type))
    return .skipChildren
  }
}

extension FunctionSignatureSyntax {
  func gatherParams() -> GatherParameters.Output {
    let gather = GatherParameters()
    gather.walk(self)
    return gather.params
  }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Analysis decls

public struct DistributedActorDecl {
  let access: AccessControl
  let name: String
  var funcs: [FuncDecl]
}

enum AccessControl: String {
  case `public`
  case `internal`
  case `private`
}

struct FuncDecl {
  let access: AccessControl
  let name: String
  let params: [(String?, String, String)]
  let throwing: Bool
  let async: Bool
  let result: String
}

