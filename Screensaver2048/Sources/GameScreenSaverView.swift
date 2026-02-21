import AppKit
import ScreenSaver
import Core2048

@objc(GameScreenSaverView)
final class GameScreenSaverView: ScreenSaverView {
  private let leaseToken: Int
  private var timer: DispatchSourceTimer?

  private let renderer = Renderer()
  private let controller: GameController

  override init?(frame: NSRect, isPreview: Bool) {
    self.leaseToken = ActiveInstanceLease.claim()

    let weights = Self.loadWeights() ?? WeightsIO.makeDefault()

    let aiDepth = isPreview ? 3 : 4
    let aiSample = isPreview ? 4 : 6
    let movesPerSecond = isPreview ? 8.0 : 12.0

    let config = GameController.Config(
      movesPerSecond: movesPerSecond,
      resetDelaySeconds: 1.0,
      ai: .init(maxDepth: aiDepth, sampleEmptyK: aiSample, ttCapacity: 150_000)
    )
    self.controller = GameController(seed: 123, weights: weights, config: config)

    super.init(frame: frame, isPreview: isPreview)
    self.animationTimeInterval = 1.0 / 30.0
  }

  required init?(coder: NSCoder) {
    self.leaseToken = ActiveInstanceLease.claim()
    let weights = Self.loadWeights() ?? WeightsIO.makeDefault()
    self.controller = GameController(seed: 123, weights: weights)
    super.init(coder: coder)
    self.animationTimeInterval = 1.0 / 30.0
  }

  deinit {
    stopTicker()
  }

  override func startAnimation() {
    super.startAnimation()
    startTicker()
  }

  override func stopAnimation() {
    super.stopAnimation()
    stopTicker()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil {
      stopTicker()
    } else {
      startTicker()
    }
  }

  override func draw(_ rect: NSRect) {
    renderer.draw(in: bounds, state: controller.state, isPreview: isPreview)
  }

  private func startTicker() {
    guard timer == nil else { return }

    let t = DispatchSource.makeTimerSource(queue: .main)
    t.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(8))
    t.setEventHandler { [weak self] in
      self?.tick()
    }
    t.resume()
    timer = t
  }

  private func stopTicker() {
    timer?.cancel()
    timer = nil
  }

  private func tick() {
    guard ActiveInstanceLease.isActive(leaseToken) else {
      // System sometimes leaves old instances alive; stop work proactively.
      stopTicker()
      return
    }

    _ = controller.step(now: ProcessInfo.processInfo.systemUptime)
    setNeedsDisplay(bounds)
  }

  private static func loadWeights() -> Weights? {
    let bundle = Bundle(for: GameScreenSaverView.self)
    guard let url = bundle.url(forResource: "weights", withExtension: "json") else { return nil }
    return try? WeightsIO.load(url: url)
  }
}

