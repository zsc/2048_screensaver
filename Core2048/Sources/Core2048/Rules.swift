public enum Move: String, CaseIterable, Codable, Sendable {
  case up
  case down
  case left
  case right
}

public struct MoveResult: Sendable {
  public let board: UInt64
  public let scoreGain: UInt32

  @inlinable
  public init(board: UInt64, scoreGain: UInt32) {
    self.board = board
    self.scoreGain = scoreGain
  }
}

public enum Rules {
  public static func applyMove(board: UInt64, move: Move) -> MoveResult? {
    switch move {
    case .left:
      return applyMoveLeft(board: board)
    case .right:
      return applyMoveRight(board: board)
    case .up:
      let t = Board64.transpose(board)
      guard let res = applyMoveLeft(board: t) else { return nil }
      return MoveResult(board: Board64.transpose(res.board), scoreGain: res.scoreGain)
    case .down:
      let t = Board64.transpose(board)
      guard let res = applyMoveRight(board: t) else { return nil }
      return MoveResult(board: Board64.transpose(res.board), scoreGain: res.scoreGain)
    }
  }

  public static func legalMoves(board: UInt64) -> [Move] {
    var moves: [Move] = []
    moves.reserveCapacity(4)
    for m in Move.allCases {
      if applyMove(board: board, move: m) != nil { moves.append(m) }
    }
    return moves
  }

  public static func isTerminal(board: UInt64) -> Bool {
    for m in Move.allCases {
      if applyMove(board: board, move: m) != nil { return false }
    }
    return true
  }

  public static func emptyCells(board: UInt64) -> [Int] {
    var cells: [Int] = []
    cells.reserveCapacity(16)
    var b = board
    for idx in 0..<16 {
      if (b & 0xF) == 0 { cells.append(idx) }
      b >>= 4
    }
    return cells
  }

  public static func spawn(board: UInt64, index: Int, exponent: UInt8) -> UInt64 {
    precondition(exponent > 0)
    precondition(Board64.getCell(board, index: index) == 0)
    return Board64.setCell(board, index: index, exponent: exponent)
  }

  public static func spawnRandom(board: UInt64, rng: inout SplitMix64) -> UInt64 {
    let empties = emptyCells(board: board)
    guard !empties.isEmpty else { return board }
    let pos = empties[rng.nextInt(upperBound: empties.count)]
    let exponent: UInt8 = (rng.nextInt(upperBound: 10) == 0) ? 2 : 1
    return spawn(board: board, index: pos, exponent: exponent)
  }

  private static func applyMoveLeft(board: UInt64) -> MoveResult? {
    var outBoard: UInt64 = 0
    var score: UInt32 = 0
    var moved = false
    for r in 0..<4 {
      let row = Board64.encodeRow(board, rowIndex: r)
      let mv = RowLookup.moveLeft(row: row)
      if mv.outRow != row { moved = true }
      outBoard |= Board64.decodeRow(mv.outRow, rowIndex: r)
      score &+= mv.scoreGain
    }
    return moved ? MoveResult(board: outBoard, scoreGain: score) : nil
  }

  private static func applyMoveRight(board: UInt64) -> MoveResult? {
    var outBoard: UInt64 = 0
    var score: UInt32 = 0
    var moved = false
    for r in 0..<4 {
      let row = Board64.encodeRow(board, rowIndex: r)
      let rev = Board64.reverseRow(row)
      let mv = RowLookup.moveLeft(row: rev)
      let outRow = Board64.reverseRow(mv.outRow)
      if outRow != row { moved = true }
      outBoard |= Board64.decodeRow(outRow, rowIndex: r)
      score &+= mv.scoreGain
    }
    return moved ? MoveResult(board: outBoard, scoreGain: score) : nil
  }
}
