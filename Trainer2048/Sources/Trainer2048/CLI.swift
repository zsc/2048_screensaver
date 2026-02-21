import Foundation

enum CLIError: Error, CustomStringConvertible {
  case message(String)

  var description: String {
    switch self {
    case .message(let s): return s
    }
  }
}

struct CLI {
  let args: [String]

  init(arguments: [String] = CommandLine.arguments) {
    self.args = Array(arguments.dropFirst())
  }

  var command: String? { args.first }

  func hasFlag(_ name: String) -> Bool {
    args.contains(name)
  }

  func value(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i &+ 1 < args.count else { return nil }
    return args[i &+ 1]
  }

  func int(_ name: String, default def: Int? = nil) throws -> Int {
    if let raw = value(name), let v = Int(raw) { return v }
    if let def { return def }
    throw CLIError.message("Missing/invalid \(name)")
  }

  func uint64(_ name: String, default def: UInt64? = nil) throws -> UInt64 {
    if let raw = value(name), let v = UInt64(raw) { return v }
    if let def { return def }
    throw CLIError.message("Missing/invalid \(name)")
  }

  func double(_ name: String, default def: Double? = nil) throws -> Double {
    if let raw = value(name), let v = Double(raw) { return v }
    if let def { return def }
    throw CLIError.message("Missing/invalid \(name)")
  }

  static func printUsage() {
    let text = """
    Usage:
      trainer init-config
      trainer eval [--weights path] [--games N] [--seed S] [--depth D] [--sample K]
      trainer train --config config.json --out weights.json
      trainer replay [--weights path] [--seed S] [--depth D] [--sample K] [--max-steps N] [--out replay.html]

    Notes:
      - If --weights is omitted, a built-in baseline is used.
      - 2048 tile exponent is 11 (2^11 = 2048).
    """
    print(text)
  }
}
