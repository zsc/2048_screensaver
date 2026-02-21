import Foundation
import Core2048

struct EvalReport {
  var games: Int
  var avgScore: Double
  var avgMaxExponent: Double
  var maxMaxExponent: Int
  var winRate2048: Double
}

enum Evaluator {
  static func runGames(
    weights: Weights,
    games: Int,
    seed: UInt64,
    depth: Int,
    sample: Int
  ) -> EvalReport {
    precondition(games > 0)
    let evaluator = LinearValueFunction(weights: weights)
    let ai = ExpectimaxAI(evaluator: evaluator, config: .init(maxDepth: depth, sampleEmptyK: sample, ttCapacity: 200_000))

    var totalScore = 0.0
    var totalMaxE = 0.0
    var wins = 0
    var maxMaxE = 0
    for i in 0..<games {
      var state = GameState.newGame(seed: seed &+ UInt64(i))
      while !state.isTerminal {
        guard let move = ai.chooseMove(state: state) else { break }
        _ = state.apply(move)
      }
      totalScore += Double(state.score)
      let maxE = Int(Board64.maxExponent(state.board))
      totalMaxE += Double(maxE)
      if maxE >= 11 { wins &+= 1 }
      if maxE > maxMaxE { maxMaxE = maxE }
    }
    return EvalReport(
      games: games,
      avgScore: totalScore / Double(games),
      avgMaxExponent: totalMaxE / Double(games),
      maxMaxExponent: maxMaxE,
      winRate2048: Double(wins) / Double(games)
    )
  }
}
