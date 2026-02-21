import Foundation
import Core2048

@main
enum TrainerMain {
  static func main() async {
    do {
      let cli = CLI()
      if cli.hasFlag("--help") || cli.command == nil {
        CLI.printUsage()
        return
      }

      switch cli.command {
      case "init-config":
        try cmdInitConfig()
      case "eval":
        try cmdEval(cli: cli)
      case "train":
        try await cmdTrain(cli: cli)
      case "replay":
        try cmdReplay(cli: cli)
      default:
        CLI.printUsage()
        throw CLIError.message("Unknown command: \(cli.command ?? "")")
      }
    } catch {
      fputs("error: \(error)\n", stderr)
      exit(1)
    }
  }

  private static func cmdInitConfig() throws {
    let config = GAConfig.default()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(config)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
  }

  private static func cmdEval(cli: CLI) throws {
    let games = try cli.int("--games", default: 50)
    let seed = try cli.uint64("--seed", default: 123)
    let depth = try cli.int("--depth", default: 3)
    let sample = try cli.int("--sample", default: 6)

    let weights: Weights
    if let path = cli.value("--weights") {
      weights = try WeightsIO.load(url: URL(fileURLWithPath: path))
    } else {
      weights = WeightsIO.makeDefault()
    }

    let t0 = Date()
    let report = Evaluator.runGames(weights: weights, games: games, seed: seed, depth: depth, sample: sample)
    let dt = Date().timeIntervalSince(t0)

    print("games: \(report.games)")
    print(String(format: "avgScore: %.1f", report.avgScore))
    print(String(format: "avgMaxExponent: %.2f", report.avgMaxExponent))
    if report.maxMaxExponent > 0, report.maxMaxExponent < 63 {
      print("maxTile: \(1 << report.maxMaxExponent) (exponent \(report.maxMaxExponent))")
    } else {
      print("maxTileExponent: \(report.maxMaxExponent)")
    }
    print(String(format: "winRate(>=2048): %.3f", report.winRate2048))
    print(String(format: "time: %.2fs", dt))
  }

  private static func cmdTrain(cli: CLI) async throws {
    guard let configPath = cli.value("--config") else {
      throw CLIError.message("Missing --config path")
    }
    guard let outPath = cli.value("--out") else {
      throw CLIError.message("Missing --out path")
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
    let config = try JSONDecoder().decode(GAConfig.self, from: data)

    var engine = GAEngine(config: config)
    let best = await engine.run()

    var params: [String: Double] = [:]
    params.reserveCapacity(GAEngine.featureKeys.count)
    for (k, v) in zip(GAEngine.featureKeys, best.genes) {
      params[k] = v
    }

    let weights = Weights(
      version: "ga-best",
      createdAt: ISO8601DateFormatter().string(from: Date()),
      params: params,
      meta: [
        "fitness": String(best.fitness),
        "avgScore": String(best.avgScore),
        "avgMaxExponent": String(best.avgMaxExponent),
        "seed": String(config.seed),
        "generations": String(config.generations),
        "populationSize": String(config.populationSize),
        "gamesPerGenome": String(config.gamesPerGenome),
        "expectimaxMaxDepth": String(config.expectimaxMaxDepth),
        "expectimaxSampleEmptyK": String(config.expectimaxSampleEmptyK),
      ]
    )

    try WeightsIO.save(weights, url: URL(fileURLWithPath: outPath))
    print("saved: \(outPath)")
  }

  private static func cmdReplay(cli: CLI) throws {
    let seed = try cli.uint64("--seed", default: 123)
    let depth = try cli.int("--depth", default: 3)
    let sample = try cli.int("--sample", default: 6)
    let maxSteps = try cli.int("--max-steps", default: 20_000)
    let outPath = cli.value("--out") ?? "replay.html"

    let weights: Weights
    if let path = cli.value("--weights") {
      weights = try WeightsIO.load(url: URL(fileURLWithPath: path))
    } else {
      weights = WeightsIO.makeDefault()
    }

    let html = try Replay.runOneGameHTML(weights: weights, seed: seed, depth: depth, sample: sample, maxSteps: maxSteps)
    guard let data = html.data(using: .utf8) else {
      throw CLIError.message("Failed to encode HTML as UTF-8")
    }
    try data.write(to: URL(fileURLWithPath: outPath), options: [.atomic])
    print("saved: \(outPath)")
  }
}
