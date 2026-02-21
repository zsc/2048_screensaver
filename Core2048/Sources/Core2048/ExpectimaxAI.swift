public protocol AIPlayer {
  func chooseMove(state: GameState) -> Move?
}

public final class ExpectimaxAI: AIPlayer {
  public struct Config: Sendable {
    public var maxDepth: Int
    public var sampleEmptyK: Int
    public var ttCapacity: Int

    public init(maxDepth: Int = 3, sampleEmptyK: Int = 6, ttCapacity: Int = 200_000) {
      self.maxDepth = max(0, maxDepth)
      self.sampleEmptyK = sampleEmptyK
      self.ttCapacity = max(0, ttCapacity)
    }
  }

  private enum NodeType: UInt8 {
    case max = 0
    case chance = 1
  }

  private let evaluator: LinearValueFunction
  private let config: Config
  private var tt: TranspositionTable

  public init(evaluator: LinearValueFunction, config: Config = Config()) {
    self.evaluator = evaluator
    self.config = config
    self.tt = TranspositionTable(capacity: config.ttCapacity)
  }

  public func chooseMove(state: GameState) -> Move? {
    let board = state.board
    let legal = Rules.legalMoves(board: board)
    guard !legal.isEmpty else { return nil }

    tt.reset()

    let empties = Board64.emptyCount(board)
    var depth = config.maxDepth
    if empties <= 2 { depth &+= 3 }
    else if empties <= 4 { depth &+= 2 }
    else if empties <= 7 { depth &+= 1 }
    depth = min(depth, 8)

    var bestMove: Move?
    var bestValue = -Double.greatestFiniteMagnitude

    for move in legal {
      guard let res = Rules.applyMove(board: board, move: move) else { continue }
      let v = Double(res.scoreGain) + expectimax(board: res.board, depth: depth &- 1, node: .chance)
      if v > bestValue {
        bestValue = v
        bestMove = move
      }
    }
    return bestMove
  }

  private func expectimax(board: UInt64, depth: Int, node: NodeType) -> Double {
    if depth <= 0 || Rules.isTerminal(board: board) {
      return evaluator.evaluate(board: board)
    }

    let key = TTKey(board: board, depth: UInt8(clamping: depth), nodeType: node.rawValue)
    if let cached = tt.value(for: key) {
      return cached
    }

    let value: Double
    switch node {
    case .max:
      var best = -Double.greatestFiniteMagnitude
      for move in Move.allCases {
        guard let res = Rules.applyMove(board: board, move: move) else { continue }
        let v = Double(res.scoreGain) + expectimax(board: res.board, depth: depth &- 1, node: .chance)
        if v > best { best = v }
      }
      value = (best == -Double.greatestFiniteMagnitude) ? evaluator.evaluate(board: board) : best
    case .chance:
      let empties = Rules.emptyCells(board: board)
      if empties.isEmpty {
        value = evaluator.evaluate(board: board)
      } else {
        let sample = sampleEmptyCells(empties, k: config.sampleEmptyK, board: board, depth: depth)
        var acc = 0.0
        let nextDepth = depth &- 1
        for idx in sample {
          let b2 = Rules.spawn(board: board, index: idx, exponent: 1)
          let b4 = Rules.spawn(board: board, index: idx, exponent: 2)
          acc += 0.9 * expectimax(board: b2, depth: nextDepth, node: .max)
          acc += 0.1 * expectimax(board: b4, depth: nextDepth, node: .max)
        }
        value = acc / Double(sample.count)
      }
    }

    tt.store(value, for: key)
    return value
  }

  private func sampleEmptyCells(_ empties: [Int], k: Int, board: UInt64, depth: Int) -> [Int] {
    guard k > 0, empties.count > k else { return empties }
    var working = empties
    var rng = SplitMix64(seed: board &+ (UInt64(depth) &* 0xD6E8_FEB8_6659_FD93))
    let kk = min(k, working.count)
    for i in 0..<kk {
      let j = i &+ rng.nextInt(upperBound: working.count &- i)
      if i != j { working.swapAt(i, j) }
    }
    return Array(working.prefix(kk))
  }
}

