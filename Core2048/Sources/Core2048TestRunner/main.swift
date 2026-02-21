import Foundation
import Core2048

enum TestError: Error, CustomStringConvertible {
  case failed(String)

  var description: String {
    switch self {
    case .failed(let s): return s
    }
  }
}

@inline(__always)
func require(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) throws {
  if !condition() { throw TestError.failed(message()) }
}

@inline(__always)
func requireEqual<T: Equatable>(_ a: T, _ b: T, _ message: @autoclosure () -> String = "") throws {
  if a != b {
    let extra = message()
    throw TestError.failed(extra.isEmpty ? "Expected \(a) == \(b)" : extra)
  }
}

@main
enum Core2048TestRunner {
  static func main() {
    do {
      let quick = CommandLine.arguments.contains("--quick")
      let t0 = Date()
      try runAll(quick: quick)
      let dt = Date().timeIntervalSince(t0)
      print(String(format: "OK (%.2fs)", dt))
    } catch {
      fputs("FAIL: \(error)\n", stderr)
      exit(1)
    }
  }

  static func runAll(quick: Bool) throws {
    try testGetSetCellRoundTrip()
    try testEncodeDecodeRowRoundTrip(iterations: quick ? 100 : 1_000)
    try testReverseRowIsInvolution()
    try testTransposeMatchesNaive(iterations: quick ? 500 : 5_000)
    try testRowLookupMatchesSlowForAllRows()
    try testApplyMoveMatchesSlowRandomBoards(iterations: quick ? 1_000 : 10_000)
    try testExpectimaxSmoke(quick: quick)
  }

  static func testGetSetCellRoundTrip() throws {
    var board: UInt64 = 0
    for idx in 0..<16 {
      board = Board64.setCell(board, index: idx, exponent: UInt8(idx % 16))
    }
    for idx in 0..<16 {
      try requireEqual(Board64.getCell(board, index: idx), UInt8(idx % 16))
    }
  }

  static func testEncodeDecodeRowRoundTrip(iterations: Int) throws {
    var rng = SplitMix64(seed: 123)
    for _ in 0..<iterations {
      var board: UInt64 = 0
      for idx in 0..<16 {
        let e = UInt8(rng.nextUInt64() & 0xF)
        board = Board64.setCell(board, index: idx, exponent: e)
      }
      var rebuilt: UInt64 = 0
      for r in 0..<4 {
        let row = Board64.encodeRow(board, rowIndex: r)
        rebuilt |= Board64.decodeRow(row, rowIndex: r)
      }
      try requireEqual(rebuilt, board)
    }
  }

  static func testReverseRowIsInvolution() throws {
    for raw in 0..<65_536 {
      let row = UInt16(raw)
      try requireEqual(Board64.reverseRow(Board64.reverseRow(row)), row)
    }
  }

  static func testTransposeMatchesNaive(iterations: Int) throws {
    func transposeSlow(_ board: UInt64) -> UInt64 {
      var out: UInt64 = 0
      for r in 0..<4 {
        for c in 0..<4 {
          let src = c * 4 + r
          let dst = r * 4 + c
          out = Board64.setCell(out, index: dst, exponent: Board64.getCell(board, index: src))
        }
      }
      return out
    }

    var rng = SplitMix64(seed: 456)
    for _ in 0..<iterations {
      var board: UInt64 = 0
      for idx in 0..<16 {
        let e = UInt8(rng.nextUInt64() & 0xF)
        board = Board64.setCell(board, index: idx, exponent: e)
      }

      let fast = Board64.transpose(board)
      let slow = transposeSlow(board)
      try requireEqual(fast, slow, "transpose mismatch:\n\(Board64.prettyDescription(board))")
      try requireEqual(Board64.transpose(fast), board)
    }
  }

  static func moveRowLeftSlow(_ row: UInt16) -> (UInt16, UInt32) {
    var tiles: [UInt8] = [
      UInt8((row >> 0) & 0xF),
      UInt8((row >> 4) & 0xF),
      UInt8((row >> 8) & 0xF),
      UInt8((row >> 12) & 0xF),
    ]
    tiles = tiles.filter { $0 != 0 }

    var merged: [UInt8] = []
    merged.reserveCapacity(4)
    var score: UInt32 = 0
    var i = 0
    while i < tiles.count {
      let cur = tiles[i]
      if i &+ 1 < tiles.count, tiles[i &+ 1] == cur {
        let nextExp = min(cur &+ 1, 0xF)
        merged.append(nextExp)
        let scoreExp = UInt32(cur) &+ 1
        if scoreExp < 32 { score &+= (UInt32(1) << scoreExp) }
        i &+= 2
      } else {
        merged.append(cur)
        i &+= 1
      }
    }
    while merged.count < 4 { merged.append(0) }

    var out: UInt16 = 0
    out |= UInt16(merged[0] & 0xF) << 0
    out |= UInt16(merged[1] & 0xF) << 4
    out |= UInt16(merged[2] & 0xF) << 8
    out |= UInt16(merged[3] & 0xF) << 12
    return (out, score)
  }

  static func testRowLookupMatchesSlowForAllRows() throws {
    for raw in 0..<65_536 {
      let row = UInt16(raw)
      let slow = moveRowLeftSlow(row)
      let fast = RowLookup.moveLeft(row: row)
      try requireEqual(fast.outRow, slow.0, "row=\(row)")
      try requireEqual(fast.scoreGain, slow.1, "row=\(row)")
    }
  }

  static func applySlow(board: UInt64, move: Move) -> MoveResult? {
    func toCells(_ b: UInt64) -> [UInt8] {
      var out: [UInt8] = []
      out.reserveCapacity(16)
      for i in 0..<16 { out.append(Board64.getCell(b, index: i)) }
      return out
    }
    func fromCells(_ cells: [UInt8]) -> UInt64 {
      precondition(cells.count == 16)
      var b: UInt64 = 0
      for i in 0..<16 {
        b = Board64.setCell(b, index: i, exponent: cells[i])
      }
      return b
    }
    func idx(_ r: Int, _ c: Int) -> Int { r * 4 + c }

    let cells = toCells(board)
    var out = cells
    var score: UInt32 = 0

    func moveLineLeft(_ line: [UInt8]) -> (out: [UInt8], score: UInt32) {
      let tiles = line.filter { $0 != 0 }
      var merged: [UInt8] = []
      merged.reserveCapacity(4)
      var score: UInt32 = 0
      var i = 0
      while i < tiles.count {
        let cur = tiles[i]
        if i &+ 1 < tiles.count, tiles[i &+ 1] == cur {
          let nextExp = min(cur &+ 1, 0xF)
          merged.append(nextExp)
          let scoreExp = UInt32(cur) &+ 1
          if scoreExp < 32 { score &+= (UInt32(1) << scoreExp) }
          i &+= 2
        } else {
          merged.append(cur)
          i &+= 1
        }
      }
      while merged.count < 4 { merged.append(0) }
      return (merged, score)
    }

    switch move {
    case .left:
      for r in 0..<4 {
        let line = (0..<4).map { cells[idx(r, $0)] }
        let res = moveLineLeft(line)
        score &+= res.score
        for c in 0..<4 { out[idx(r, c)] = res.out[c] }
      }
    case .right:
      for r in 0..<4 {
        let line = (0..<4).map { cells[idx(r, 3 - $0)] }
        let res = moveLineLeft(line)
        score &+= res.score
        for c in 0..<4 { out[idx(r, 3 - c)] = res.out[c] }
      }
    case .up:
      for c in 0..<4 {
        let line = (0..<4).map { cells[idx($0, c)] }
        let res = moveLineLeft(line)
        score &+= res.score
        for r in 0..<4 { out[idx(r, c)] = res.out[r] }
      }
    case .down:
      for c in 0..<4 {
        let line = (0..<4).map { cells[idx(3 - $0, c)] }
        let res = moveLineLeft(line)
        score &+= res.score
        for r in 0..<4 { out[idx(3 - r, c)] = res.out[r] }
      }
    }

    let outBoard = fromCells(out)
    return outBoard == board ? nil : MoveResult(board: outBoard, scoreGain: score)
  }

  static func testApplyMoveMatchesSlowRandomBoards(iterations: Int) throws {
    var rng = SplitMix64(seed: 999)
    for _ in 0..<iterations {
      var board: UInt64 = 0
      for i in 0..<16 {
        let x = rng.nextUInt64() % 10
        let e: UInt8 = x < 6 ? 0 : UInt8((rng.nextUInt64() % 6) + 1) // exponents 1..6
        board = Board64.setCell(board, index: i, exponent: e)
      }

      for m in Move.allCases {
        let fast = Rules.applyMove(board: board, move: m)
        let slow = applySlow(board: board, move: m)
        if fast?.board != slow?.board || fast?.scoreGain != slow?.scoreGain {
          throw TestError.failed(
            "applyMove mismatch (move=\(m))\nboard:\n\(Board64.prettyDescription(board))\nfast:\n\(fast.map { Board64.prettyDescription($0.board) } ?? "nil")\nslow:\n\(slow.map { Board64.prettyDescription($0.board) } ?? "nil")"
          )
        }
      }
    }
  }

  static func testExpectimaxSmoke(quick: Bool) throws {
    // Terminal board: alternating 2/4.
    let exps: [UInt8] = [
      1, 2, 1, 2,
      2, 1, 2, 1,
      1, 2, 1, 2,
      2, 1, 2, 1,
    ]
    var terminal: UInt64 = 0
    for i in 0..<16 {
      terminal = Board64.setCell(terminal, index: i, exponent: exps[i])
    }
    try require(Rules.isTerminal(board: terminal), "Expected terminal board")

    let ai = ExpectimaxAI(evaluator: LinearValueFunction(weights: WeightsIO.makeDefault()))
    let terminalState = GameState(board: terminal, score: 0, rng: SplitMix64(seed: 0))
    try require(ai.chooseMove(state: terminalState) == nil, "AI should return nil on terminal")

    // Determinism on a fresh game board.
    let state = GameState.newGame(seed: 42)
    let m1 = ai.chooseMove(state: state)
    let m2 = ai.chooseMove(state: state)
    try requireEqual(m1, m2, "Non-deterministic chooseMove on same state")
    try require(m1 != nil, "AI returned nil on non-terminal state")

    // Autoplay terminates.
    var s = GameState.newGame(seed: 7)
    var steps = 0
    while !s.isTerminal {
      guard let move = ai.chooseMove(state: s) else { break }
      _ = s.apply(move)
      steps &+= 1
      if steps > 50_000 { throw TestError.failed("Game did not terminate after 50k steps") }
    }
    try require(steps > 0, "Expected at least one move")

    // Reproducibility: same seed -> same final score/max tile.
    func play(seed: UInt64) -> (score: UInt64, maxE: UInt8) {
      var gs = GameState.newGame(seed: seed)
      while !gs.isTerminal {
        guard let move = ai.chooseMove(state: gs) else { break }
        _ = gs.apply(move)
      }
      return (gs.score, Board64.maxExponent(gs.board))
    }
    let r1 = play(seed: 99)
    let r2 = play(seed: 99)
    try requireEqual(r1.score, r2.score, "Non-reproducible final score for same seed")
    try requireEqual(r1.maxE, r2.maxE, "Non-reproducible max exponent for same seed")

    // Basic quality sanity check (deterministic): average over a few seeds.
    if !quick {
      let games = 10
      var total = 0.0
      var totalMax = 0.0
      for i in 0..<games {
        var gs = GameState.newGame(seed: UInt64(1000 + i))
        while !gs.isTerminal {
          guard let move = ai.chooseMove(state: gs) else { break }
          _ = gs.apply(move)
        }
        total += Double(gs.score)
        totalMax += Double(Board64.maxExponent(gs.board))
      }
      let avgScore = total / Double(games)
      let avgMax = totalMax / Double(games)
      // Very lenient guards to catch catastrophic regressions.
      try require(avgScore >= 1_500, "avgScore too low: \(avgScore)")
      try require(avgMax >= 9.0, "avgMaxExponent too low: \(avgMax)")
    }
  }
}
