//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-sample-distributed-actors-transport open source project
//
// Copyright (c) 2021 Apple Inc. and the swift-sample-distributed-actors-transport project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of swift-sample-distributed-actors-transport project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import Logging

internal let CONSOLE_RESET = "\u{001B}[0;0m"
internal let CONSOLE_BOLD = "\u{001B}[1m"
internal let CONSOLE_YELLOW = "\u{001B}[0;33m"
internal let CONSOLE_GREEN = "\u{001B}[0;32m"

/// "Pretty" log handler that is optimized for demo and human-readability purposes.
struct PrettyDemoLogHandler: LogHandler {
  public static func _createFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "y-MM-dd H:m:ss.SSSS"
    formatter.locale = Locale(identifier: "en_US")
    formatter.calendar = Calendar(identifier: .gregorian)
    return formatter
  }

  let label: String
  internal init(label: String) {
    self.label = label
  }

  public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, file: String, function: String, line: UInt) {
    var msg = ""
    msg += "\(formatLevel(level))"
    msg += "[\(file.split(separator: "/").last ?? "<unknown-file>"):\(line)]" // we only print "file" rather than full path
    msg += "[\(label)]"
    msg += " \(message)"

    // "pretty" logging
    if let metadata = metadata, !metadata.isEmpty {
      var metadataString = "\n// metadata:\n"
      for key in metadata.keys.sorted() where key != "label" {
        var allString = "\n// \"\(key)\": \(metadata[key]!)"
        if allString.contains("\n") {
          allString = String(
              allString.split(separator: "\n").map { valueLine in
                if valueLine.starts(with: "// ") {
                  return "\(valueLine)\n"
                } else {
                  return "// \(valueLine)\n"
                }
              }.joined(separator: "")
          )
        }
        metadataString.append(allString)
      }
      metadataString = String(metadataString.dropLast(1))

      msg += metadataString
    }

    print(msg)
  }

  public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
    get {
      nil
    }
    set {
      // ignore
    }
  }

  public var logLevel: Logger.Level = .info

  public var metadata: Logger.Metadata = [:]

  private func formatLevel(_ level: Logger.Level) -> String {
    switch level {
    case .trace: return "[TRACE]"
    case .debug: return "[DEBUG]"
    case .info: return "[INFO]"
    case .notice: return "[NOTICE]"
    case .warning: return "[WARN]"
    case .error: return "[ERROR]"
    case .critical: return "[CRITICAL]"
    }
  }
}

/// Message carrying all information needed to log a log statement issued by a `Logger`.
///
/// This can be used to offload the action of actually writing the log statements to an asynchronous worker actor.
/// This is useful to not block the (current) actors processing with any potential IO operations a `LogHandler` may
/// need to perform.
public struct LogMessage {
  let identifier: String

  let time: Date
  let level: Logger.Level
  let message: Logger.Message
  var effectiveMetadata: Logger.Metadata?

  let file: String
  let function: String
  let line: UInt
}

extension Logger.MetadataValue {
  public static func pretty<T>(_ value: T) -> Logger.Metadata.Value where T: CustomPrettyStringConvertible {
    Logger.MetadataValue.stringConvertible(CustomPrettyStringConvertibleMetadataValue(value))
  }

  public static func pretty<T>(_ value: T) -> Logger.Metadata.Value {
    if let pretty = value as? CustomPrettyStringConvertible {
      return Logger.MetadataValue.stringConvertible(CustomPrettyStringConvertibleMetadataValue(pretty))
    } else {
      return .string("\(value)")
    }
  }
}

struct CustomPrettyStringConvertibleMetadataValue: CustomStringConvertible {
  let value: CustomPrettyStringConvertible

  init(_ value: CustomPrettyStringConvertible) {
    self.value = value
  }

  var description: String {
    "\(self.value)"
  }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Pretty String Descriptions

/// Marks a type that can be "pretty" printed, meaning often multi-line well formatted/aligned.
public protocol CustomPrettyStringConvertible {
  /// Pretty representation of the type, intended for inspection in command line and "visual" inspection.
  /// Not to be used in log statements or otherwise persisted formats.
  var prettyDescription: String { get }
  func prettyDescription(depth: Int) -> String
}

extension CustomPrettyStringConvertible {
  public var prettyDescription: String {
    self.prettyDescription(depth: 0)
  }

  public func prettyDescription(depth: Int) -> String {
    self.prettyDescription(of: self, depth: depth)
  }

  public func prettyDescription(of value: Any, depth: Int) -> String {
    let mirror = Mirror(reflecting: value)
    let padding0 = String(repeating: " ", count: depth * 2)
    let padding1 = String(repeating: " ", count: (depth + 1) * 2)

    var res = "\(Self.self)(\n"
    for member in mirror.children {
      res += "\(padding1)"
      res += "\(CONSOLE_BOLD)\(optional: member.label)\(CONSOLE_RESET): "
      switch member.value {
      case let v as CustomPrettyStringConvertible:
        res += v.prettyDescription(depth: depth + 1)
      case let v as ExpressibleByNilLiteral:
        let description = "\(v)"
        if description.starts(with: "Optional(") {
          var r = description.dropFirst("Optional(".count)
          r = r.dropLast(1)
          res += "\(r)"
        } else {
          res += "nil"
        }
      case let v as CustomDebugStringConvertible:
        res += v.debugDescription
      default:
        res += "\(member.value)"
      }
      res += ",\n"
    }
    res += "\(padding0))"

    return res
  }
}

extension Set: CustomPrettyStringConvertible {
  public var prettyDescription: String {
    self.prettyDescription(depth: 0)
  }

  public func prettyDescription(depth: Int) -> String {
    self.prettyDescription(of: self, depth: depth)
  }

  public func prettyDescription(of value: Any, depth: Int) -> String {
    let padding0 = String(repeating: " ", count: depth * 2)
    let padding1 = String(repeating: " ", count: (depth + 1) * 2)

    var res = "[\n"
    for element in self {
      res += "\(padding1)\(element),\n"
    }
    res += "\(padding0)]"
    return res
  }
}

extension Array: CustomPrettyStringConvertible {
  public var prettyDescription: String {
    self.prettyDescription(depth: 0)
  }

  public func prettyDescription(depth: Int) -> String {
    self.prettyDescription(of: self, depth: depth)
  }

  public func prettyDescription(of value: Any, depth: Int) -> String {
    let padding0 = String(repeating: " ", count: depth * 2)
    let padding1 = String(repeating: " ", count: (depth + 1) * 2)

    var res = "Set([\n"
    for element in self {
      res += "\(padding1)\(element),\n"
    }
    res += "\(padding0)])"
    return res
  }
}

extension Dictionary: CustomPrettyStringConvertible {
  public var prettyDescription: String {
    self.prettyDescription(depth: 0)
  }

  public func prettyDescription(depth: Int) -> String {
    self.prettyDescription(of: self, depth: depth)
  }

  public func prettyDescription(of value: Any, depth: Int) -> String {
    let padding0 = String(repeating: " ", count: depth * 2)
    let padding1 = String(repeating: " ", count: (depth + 1) * 2)

    var res = "[\n"
    for key in self.keys.sorted(by: { "\($0)" < "\($1)" }) {
      res += "\(padding1)\(key): \(self[key]!),\n"
    }
    res += "\(padding0)]"
    return res
  }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: String Interpolation: _:leftPad:

internal extension String.StringInterpolation {
  mutating func appendInterpolation(_ value: CustomStringConvertible, leftPadTo totalLength: Int) {
    let s = "\(value)"
    let pad = String(repeating: " ", count: max(totalLength - s.count, 0))
    self.appendLiteral("\(pad)\(s)")
  }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: String Interpolation: Message printing [contents]:type which is useful for enums

internal extension String.StringInterpolation {
  mutating func appendInterpolation(message: Any) {
    self.appendLiteral("[\(message)]:\(String(reflecting: type(of: message)))")
  }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: String Interpolation: optionals

public extension String.StringInterpolation {
  mutating func appendInterpolation<T>(_ value: T?, orElse defaultValue: String) {
    self.appendLiteral("\(value.map { "\($0)" } ?? defaultValue)")
  }

  mutating func appendInterpolation<T>(optional value: T?) {
    self.appendLiteral("\(value.map { "\($0)" } ?? "nil")")
  }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: String Interpolation: reflecting:

internal extension String.StringInterpolation {
  mutating func appendInterpolation(pretty subject: Any) {
    if let prettySubject = subject as? CustomPrettyStringConvertible {
      self.appendLiteral(prettySubject.prettyDescription)
    } else {
      self.appendLiteral("\(reflecting: subject)")
    }
  }

  mutating func appendInterpolation(reflecting subject: Any?) {
    self.appendLiteral(String(reflecting: subject))
  }

  mutating func appendInterpolation(reflecting subject: Any) {
    self.appendLiteral(String(reflecting: subject))
  }
}

internal extension String.StringInterpolation {
  mutating func appendInterpolation(lineByLine subject: [Any]) {
    self.appendLiteral("\n    \(subject.map { "\($0)" }.joined(separator: "\n    "))")
  }
}