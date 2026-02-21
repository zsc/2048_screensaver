import Foundation

struct GAConfig: Codable, Sendable {
  var seed: UInt64
  var generations: Int
  var populationSize: Int
  var elitism: Int
  var tournamentSize: Int
  var mutationRate: Double
  var mutationSigma: Double
  var crossoverAlpha: Double
  var weightMin: Double
  var weightMax: Double

  var gamesPerGenome: Int
  var fitnessMaxExponentWeight: Double

  var expectimaxMaxDepth: Int
  var expectimaxSampleEmptyK: Int
  var expectimaxTTCapacity: Int

  static func `default`() -> GAConfig {
    GAConfig(
      seed: 123,
      generations: 30,
      populationSize: 96,
      elitism: 8,
      tournamentSize: 5,
      mutationRate: 0.3,
      mutationSigma: 0.35,
      crossoverAlpha: 0.25,
      weightMin: -5,
      weightMax: 5,
      gamesPerGenome: 16,
      fitnessMaxExponentWeight: 1000,
      expectimaxMaxDepth: 3,
      expectimaxSampleEmptyK: 6,
      expectimaxTTCapacity: 200_000
    )
  }
}

