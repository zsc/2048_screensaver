import Foundation

public final class GameController {
  public struct Config: Sendable {
    public var movesPerSecond: Double
    public var resetDelaySeconds: Double
    public var ai: ExpectimaxAI.Config

    public init(
      movesPerSecond: Double = 10,
      resetDelaySeconds: Double = 1.0,
      ai: ExpectimaxAI.Config = .init()
    ) {
      self.movesPerSecond = movesPerSecond
      self.resetDelaySeconds = resetDelaySeconds
      self.ai = ai
    }
  }

  public private(set) var state: GameState
  public let ai: ExpectimaxAI
  public var config: Config

  private var lastMoveTime: TimeInterval = 0
  private var gameOverTime: TimeInterval?

  public init(seed: UInt64, weights: Weights, config: Config = Config()) {
    self.config = config
    self.state = GameState.newGame(seed: seed)
    self.ai = ExpectimaxAI(evaluator: LinearValueFunction(weights: weights), config: config.ai)
  }

  public func reset(seed: UInt64? = nil, now: TimeInterval = 0) {
    let nextSeed = seed ?? state.rng.nextUInt64()
    state = GameState.newGame(seed: nextSeed)
    lastMoveTime = now
    gameOverTime = nil
  }

  /// Advances the game at most one move if enough time has elapsed.
  /// - Returns: `true` if state changed.
  public func step(now: TimeInterval) -> Bool {
    if state.isTerminal {
      if gameOverTime == nil { gameOverTime = now }
      if let gameOverTime, now - gameOverTime >= config.resetDelaySeconds {
        reset(seed: nil, now: now)
        return true
      }
      return false
    }

    gameOverTime = nil

    let mps = max(0.0, config.movesPerSecond)
    guard mps > 0 else { return false }
    let interval = 1.0 / mps
    guard (now - lastMoveTime) >= interval else { return false }
    lastMoveTime = now

    if let move = ai.chooseMove(state: state), state.apply(move) {
      return true
    }

    // Fallback: try any legal move (should be rare unless AI is misconfigured).
    for m in Rules.legalMoves(board: state.board) {
      if state.apply(m) { return true }
    }
    return false
  }
}

