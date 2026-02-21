import Foundation

public struct Weights: Codable, Sendable {
  public var version: String
  public var createdAt: String
  public var params: [String: Double]
  public var meta: [String: String]?

  public init(version: String, createdAt: String, params: [String: Double], meta: [String: String]? = nil) {
    self.version = version
    self.createdAt = createdAt
    self.params = params
    self.meta = meta
  }
}

public protocol BoardEvaluator {
  func evaluate(board: UInt64) -> Double
}

public struct LinearValueFunction: BoardEvaluator, Sendable {
  public static let featureKeys: [String] = [
    "f_empty",
    "f_max",
    "f_smooth",
    "f_mono",
    "f_mergePotential",
    "f_cornerMax",
  ]

  public let weights: Weights

  private let wEmpty: Double
  private let wMax: Double
  private let wSmooth: Double
  private let wMono: Double
  private let wMergePotential: Double
  private let wCornerMax: Double

  public init(weights: Weights) {
    self.weights = weights
    func w(_ k: String, _ alt: String? = nil) -> Double {
      if let v = weights.params[k] { return v }
      if let alt, let v = weights.params[alt] { return v }
      return 0
    }
    self.wEmpty = w("f_empty", "empty")
    self.wMax = w("f_max", "max")
    self.wSmooth = w("f_smooth", "smooth")
    self.wMono = w("f_mono", "mono")
    self.wMergePotential = w("f_mergePotential", "mergePotential")
    self.wCornerMax = w("f_cornerMax", "cornerMax")
  }

  public func evaluate(board: UInt64) -> Double {
    let empty = Double(Board64.emptyCount(board))
    let maxE = Double(Board64.maxExponent(board))

    let f = Self.features(board: board, maxExponent: UInt8(maxE))
    return (wEmpty * empty)
      + (wMax * maxE)
      + (wSmooth * f.smooth)
      + (wMono * f.mono)
      + (wMergePotential * f.mergePotential)
      + (wCornerMax * f.cornerMax)
  }

  static func features(board: UInt64, maxExponent: UInt8? = nil) -> (
    smooth: Double,
    mono: Double,
    mergePotential: Double,
    cornerMax: Double
  ) {
    let t = Board64.transpose(board)

    var smooth: Int = 0
    var mono: Int = 0
    var merge: Int = 0

    for r in 0..<4 {
      let row = Board64.encodeRow(board, rowIndex: r)
      let rowI = Int(row)
      smooth &+= Int(RowEvalLookup.smooth[rowI])
      mono &+= Int(RowEvalLookup.mono[rowI])
      merge &+= Int(RowEvalLookup.mergePotential[rowI])

      let col = Board64.encodeRow(t, rowIndex: r)
      let colI = Int(col)
      smooth &+= Int(RowEvalLookup.smooth[colI])
      mono &+= Int(RowEvalLookup.mono[colI])
      merge &+= Int(RowEvalLookup.mergePotential[colI])
    }

    let maxE = maxExponent ?? Board64.maxExponent(board)
    let cornerIdx = [0, 3, 12, 15]
    var cornerBonus = 0.0
    for idx in cornerIdx {
      if Board64.getCell(board, index: idx) == maxE {
        cornerBonus = Double(maxE)
        break
      }
    }

    return (
      smooth: Double(smooth),
      mono: Double(mono),
      mergePotential: Double(merge),
      cornerMax: cornerBonus
    )
  }
}

public enum RowEvalLookup {
  public static let smooth: [Int16] = buildSmooth()
  public static let mono: [Int16] = buildMono()
  public static let mergePotential: [UInt8] = buildMergePotential()

  private static func buildSmooth() -> [Int16] {
    var out = Array(repeating: Int16(0), count: 65_536)
    for raw in 0..<65_536 {
      let row = UInt16(raw)
      let a = UInt8((row >> 0) & 0xF)
      let b = UInt8((row >> 4) & 0xF)
      let c = UInt8((row >> 8) & 0xF)
      let d = UInt8((row >> 12) & 0xF)
      var s: Int = 0
      s &+= smoothPair(a, b)
      s &+= smoothPair(b, c)
      s &+= smoothPair(c, d)
      out[raw] = Int16(clamping: s)
    }
    return out
  }

  private static func smoothPair(_ x: UInt8, _ y: UInt8) -> Int {
    guard x != 0, y != 0 else { return 0 }
    let dx = Int(x) - Int(y)
    return -abs(dx)
  }

  private static func buildMono() -> [Int16] {
    var out = Array(repeating: Int16(0), count: 65_536)
    for raw in 0..<65_536 {
      let row = UInt16(raw)
      let a = Int((row >> 0) & 0xF)
      let b = Int((row >> 4) & 0xF)
      let c = Int((row >> 8) & 0xF)
      let d = Int((row >> 12) & 0xF)

      // Monotonicity as negative penalty: closer to 0 is better.
      var inc = 0
      var dec = 0
      monoStep(a, b, &inc, &dec)
      monoStep(b, c, &inc, &dec)
      monoStep(c, d, &inc, &dec)
      let penalty = min(inc, dec)
      out[raw] = Int16(clamping: -penalty)
    }
    return out
  }

  private static func monoStep(_ x: Int, _ y: Int, _ inc: inout Int, _ dec: inout Int) {
    if x > y {
      dec &+= x &- y
    } else {
      inc &+= y &- x
    }
  }

  private static func buildMergePotential() -> [UInt8] {
    var out = Array(repeating: UInt8(0), count: 65_536)
    for raw in 0..<65_536 {
      let row = UInt16(raw)
      let a = UInt8((row >> 0) & 0xF)
      let b = UInt8((row >> 4) & 0xF)
      let c = UInt8((row >> 8) & 0xF)
      let d = UInt8((row >> 12) & 0xF)
      var m: UInt8 = 0
      if a != 0, a == b { m &+= 1 }
      if b != 0, b == c { m &+= 1 }
      if c != 0, c == d { m &+= 1 }
      out[raw] = m
    }
    return out
  }
}

public enum WeightsIO {
  public static func load(url: URL) throws -> Weights {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Weights.self, from: data)
  }

  public static func save(_ weights: Weights, url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(weights)
    try data.write(to: url, options: [.atomic])
  }

  public static func makeDefault() -> Weights {
    // Reasonable hand-tuned baseline; GA can improve from here.
    Weights(
      version: "baseline-v1",
      createdAt: ISO8601DateFormatter().string(from: Date()),
      params: [
        "f_empty": 2.7,
        "f_max": 1.0,
        "f_smooth": 0.1,
        "f_mono": 1.0,
        "f_mergePotential": 0.7,
        "f_cornerMax": 0.5,
      ]
    )
  }
}
