public struct GameState: Sendable {
  public var board: UInt64
  public var score: UInt64
  public var rng: SplitMix64

  @inlinable
  public init(board: UInt64, score: UInt64, rng: SplitMix64) {
    self.board = board
    self.score = score
    self.rng = rng
  }

  @inlinable
  public static func newGame(seed: UInt64) -> GameState {
    var rng = SplitMix64(seed: seed)
    var board: UInt64 = 0
    board = Rules.spawnRandom(board: board, rng: &rng)
    board = Rules.spawnRandom(board: board, rng: &rng)
    return GameState(board: board, score: 0, rng: rng)
  }

  @inlinable
  public var isTerminal: Bool {
    Rules.isTerminal(board: board)
  }

  @inlinable
  public mutating func apply(_ move: Move) -> Bool {
    guard let res = Rules.applyMove(board: board, move: move) else { return false }
    board = res.board
    score &+= UInt64(res.scoreGain)
    board = Rules.spawnRandom(board: board, rng: &rng)
    return true
  }
}

