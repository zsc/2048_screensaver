import Foundation
import Core2048

struct Genome: Sendable {
  var genes: [Double]
  var fitness: Double
  var avgScore: Double
  var avgMaxExponent: Double

  init(genes: [Double], fitness: Double = .nan, avgScore: Double = .nan, avgMaxExponent: Double = .nan) {
    self.genes = genes
    self.fitness = fitness
    self.avgScore = avgScore
    self.avgMaxExponent = avgMaxExponent
  }
}

struct GAEngine {
  static let featureKeys = LinearValueFunction.featureKeys

  var config: GAConfig
  var rng: SplitMix64

  init(config: GAConfig) {
    self.config = config
    self.rng = SplitMix64(seed: config.seed)
  }

  mutating func run() async -> Genome {
    let geneCount = Self.featureKeys.count
    precondition(geneCount > 0)

    var population: [Genome] = []
    population.reserveCapacity(config.populationSize)

    // Seed population around the built-in baseline.
    let baseline = WeightsIO.makeDefault()
    var baselineGenes: [Double] = []
    baselineGenes.reserveCapacity(geneCount)
    for k in Self.featureKeys {
      baselineGenes.append(baseline.params[k] ?? 0)
    }

    population.append(Genome(genes: clampGenes(baselineGenes)))
    while population.count < config.populationSize {
      var genes: [Double] = []
      genes.reserveCapacity(geneCount)
      for i in 0..<geneCount {
        let base = baselineGenes[i]
        let v = base + nextGaussian() * config.mutationSigma * 2
        genes.append(v)
      }
      population.append(Genome(genes: clampGenes(genes)))
    }

    for gen in 0..<config.generations {
      population = await Self.evaluatePopulation(population, generation: gen, config: config)
      population.sort { $0.fitness > $1.fitness }

      let stats = summarize(population)
      print(
        String(
          format: "gen %3d | best %.1f (score %.0f, maxExp %.2f) | mean %.1f | std %.1f",
          gen,
          stats.best.fitness,
          stats.best.avgScore,
          stats.best.avgMaxExponent,
          stats.meanFitness,
          stats.stdFitness
        )
      )

      if gen &+ 1 == config.generations { break }

      population = breedNextGeneration(from: population)
    }

    population.sort { $0.fitness > $1.fitness }
    return population[0]
  }

  private func summarize(_ pop: [Genome]) -> (best: Genome, meanFitness: Double, stdFitness: Double) {
    let best = pop[0]
    let mean = pop.map(\.fitness).reduce(0, +) / Double(pop.count)
    let variance = pop.map { ($0.fitness - mean) * ($0.fitness - mean) }.reduce(0, +) / Double(pop.count)
    return (best, mean, sqrt(variance))
  }

  private mutating func breedNextGeneration(from pop: [Genome]) -> [Genome] {
    let n = config.populationSize
    let e = min(max(0, config.elitism), n)
    var next: [Genome] = Array(pop.prefix(e))
    next.reserveCapacity(n)
    while next.count < n {
      let p1 = tournamentSelect(pop)
      let p2 = tournamentSelect(pop)
      let childGenes = mutate(crossover(p1.genes, p2.genes))
      next.append(Genome(genes: childGenes))
    }
    return next
  }

  private mutating func tournamentSelect(_ pop: [Genome]) -> Genome {
    let t = min(max(2, config.tournamentSize), pop.count)
    var best = pop[rng.nextInt(upperBound: pop.count)]
    if t == 1 { return best }
    for _ in 1..<t {
      let g = pop[rng.nextInt(upperBound: pop.count)]
      if g.fitness > best.fitness { best = g }
    }
    return best
  }

  private mutating func crossover(_ a: [Double], _ b: [Double]) -> [Double] {
    precondition(a.count == b.count)
    let alpha = max(0, config.crossoverAlpha)
    var out = a
    for i in 0..<out.count {
      let lo = min(a[i], b[i])
      let hi = max(a[i], b[i])
      let range = hi - lo
      let minV = lo - alpha * range
      let maxV = hi + alpha * range
      out[i] = minV + (maxV - minV) * nextUniform01()
    }
    return clampGenes(out)
  }

  private mutating func mutate(_ genes: [Double]) -> [Double] {
    var out = genes
    for i in 0..<out.count {
      if nextUniform01() < config.mutationRate {
        out[i] += nextGaussian() * config.mutationSigma
      }
    }
    return clampGenes(out)
  }

  private func clampGenes(_ genes: [Double]) -> [Double] {
    genes.map { min(config.weightMax, max(config.weightMin, $0)) }
  }

  private static func makeWeightsForEval(from genes: [Double]) -> Weights {
    var params: [String: Double] = [:]
    params.reserveCapacity(Self.featureKeys.count)
    for (k, v) in zip(Self.featureKeys, genes) {
      params[k] = v
    }
    return Weights(
      version: "eval",
      createdAt: "n/a",
      params: params
    )
  }

  private static func evaluatePopulation(_ pop: [Genome], generation: Int, config: GAConfig) async -> [Genome] {
    let maxParallel = max(1, ProcessInfo.processInfo.activeProcessorCount)
    var next: [Genome] = []
    next.reserveCapacity(pop.count)

    await withTaskGroup(of: (Int, Genome).self) { group in
      var submitted = 0

      func submit(_ idx: Int) {
        group.addTask {
          let genomeIndex = generation * 1_000_000 &+ idx
          let evaluated = Self.evaluateGenome(pop[idx], genomeIndex: genomeIndex, config: config)
          return (idx, evaluated)
        }
      }

      while submitted < min(maxParallel, pop.count) {
        submit(submitted)
        submitted &+= 1
      }

      var results = Array(repeating: Genome(genes: []), count: pop.count)
      var received = 0
      while let (idx, g) = await group.next() {
        results[idx] = g
        received &+= 1

        if submitted < pop.count {
          submit(submitted)
          submitted &+= 1
        }
      }

      precondition(received == pop.count)
      next = results
    }
    return next
  }

  private static func evaluateGenome(_ genome: Genome, genomeIndex: Int, config: GAConfig) -> Genome {
    let weights = makeWeightsForEval(from: genome.genes)
    let evaluator = LinearValueFunction(weights: weights)
    let ai = ExpectimaxAI(
      evaluator: evaluator,
      config: .init(
        maxDepth: config.expectimaxMaxDepth,
        sampleEmptyK: config.expectimaxSampleEmptyK,
        ttCapacity: config.expectimaxTTCapacity
      )
    )

    var totalScore = 0.0
    var totalMaxE = 0.0
    for gameIndex in 0..<config.gamesPerGenome {
      let seed = config.seed &+ UInt64(genomeIndex) &* 1_000_000 &+ UInt64(gameIndex)
      var state = GameState.newGame(seed: seed)
      while !state.isTerminal {
        guard let move = ai.chooseMove(state: state) else { break }
        _ = state.apply(move)
      }
      totalScore += Double(state.score)
      totalMaxE += Double(Board64.maxExponent(state.board))
    }

    let games = Double(config.gamesPerGenome)
    let avgScore = totalScore / games
    let avgMaxE = totalMaxE / games
    let fitness = avgScore + config.fitnessMaxExponentWeight * avgMaxE
    return Genome(genes: genome.genes, fitness: fitness, avgScore: avgScore, avgMaxExponent: avgMaxE)
  }

  private mutating func nextUniform01() -> Double {
    // 53-bit precision uniform in [0, 1).
    let x = rng.nextUInt64() >> 11
    return Double(x) / Double(1 << 53)
  }

  private mutating func nextGaussian() -> Double {
    // Box-Muller
    let u1 = max(nextUniform01(), 1e-12)
    let u2 = nextUniform01()
    return sqrt(-2 * log(u1)) * cos(2 * Double.pi * u2)
  }
}
