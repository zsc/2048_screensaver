import AppKit
import ScreenSaver
import Core2048

@objc(GameScreenSaverView)
final class GameScreenSaverView: ScreenSaverView {
  private let leaseToken: Int
  private var timer: DispatchSourceTimer?

  private let renderer = Renderer()
  private let controller: GameController
  private var boardOrigin: CGPoint?
  private var boardVelocity: CGVector = .zero
  private var motionLastUptime: TimeInterval?

  override init?(frame: NSRect, isPreview: Bool) {
    self.leaseToken = ActiveInstanceLease.claim()

    let weights = Self.loadWeights() ?? WeightsIO.makeDefault()

    let aiDepth = isPreview ? 3 : 4
    let aiSample = isPreview ? 4 : 6
    let movesPerSecond = isPreview ? 2.5 : 3.5

    let config = GameController.Config(
      movesPerSecond: movesPerSecond,
      resetDelaySeconds: 2.0,
      ai: .init(maxDepth: aiDepth, sampleEmptyK: aiSample, ttCapacity: 150_000)
    )
    self.controller = GameController(seed: 123, weights: weights, config: config)

    super.init(frame: frame, isPreview: isPreview)
    self.animationTimeInterval = 1.0 / 30.0
  }

  required init?(coder: NSCoder) {
    self.leaseToken = ActiveInstanceLease.claim()
    let weights = Self.loadWeights() ?? WeightsIO.makeDefault()
    let config = GameController.Config(
      movesPerSecond: 3.0,
      resetDelaySeconds: 2.0,
      ai: .init(maxDepth: 4, sampleEmptyK: 6, ttCapacity: 150_000)
    )
    self.controller = GameController(seed: 123, weights: weights, config: config)
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
    let layout = Renderer.makeLayout(bounds: bounds, isPreview: isPreview)
    renderer.draw(layout: layout, state: controller.state, boardOrigin: boardOrigin)
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

    let now = ProcessInfo.processInfo.systemUptime
    let layout = Renderer.makeLayout(bounds: bounds, isPreview: isPreview)
    updateBoardMotion(now: now, layout: layout)
    _ = controller.step(now: now)
    setNeedsDisplay(bounds)
  }

  private func updateBoardMotion(now: TimeInterval, layout: Renderer.Layout) {
    let minO = layout.minBoardOrigin
    let maxO = layout.maxBoardOrigin
    if maxO.x <= minO.x || maxO.y <= minO.y {
      boardOrigin = layout.centeredBoardOrigin
      motionLastUptime = now
      boardVelocity = .zero
      return
    }

    if boardOrigin == nil {
      boardOrigin = layout.centeredBoardOrigin
      let base = min(layout.contentRect.width, layout.contentRect.height)
      let factor: CGFloat = isPreview ? 0.020 : 0.012
      let speed = max(CGFloat(4.0), base * factor) // points/sec
      let golden: CGFloat = 0.61803398875
      boardVelocity = CGVector(dx: speed, dy: speed * golden)
      motionLastUptime = now
      return
    }

    guard let last = motionLastUptime else {
      motionLastUptime = now
      return
    }
    let dt = now - last
    motionLastUptime = now
    guard dt > 0 else { return }

    var origin = layout.clampedBoardOrigin(boardOrigin ?? layout.centeredBoardOrigin)
    var vx = boardVelocity.dx
    var vy = boardVelocity.dy

    advanceAxis(&origin.x, &vx, min: minO.x, max: maxO.x, dt: dt)
    advanceAxis(&origin.y, &vy, min: minO.y, max: maxO.y, dt: dt)

    boardOrigin = origin
    boardVelocity = CGVector(dx: vx, dy: vy)
  }

  private func advanceAxis(_ pos: inout CGFloat, _ vel: inout CGFloat, min: CGFloat, max: CGFloat, dt: TimeInterval) {
    if max <= min {
      pos = min
      vel = 0
      return
    }
    pos += vel * CGFloat(dt)
    while pos < min || pos > max {
      if pos < min {
        pos = min + (min - pos)
        vel = abs(vel)
      } else if pos > max {
        pos = max - (pos - max)
        vel = -abs(vel)
      }
    }
  }

  private static func loadWeights() -> Weights? {
    let bundle = Bundle(for: GameScreenSaverView.self)
    guard let url = bundle.url(forResource: "weights", withExtension: "json") else { return nil }
    return try? WeightsIO.load(url: url)
  }
}
