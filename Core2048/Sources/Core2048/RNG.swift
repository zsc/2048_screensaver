public struct SplitMix64: Sendable {
  public private(set) var state: UInt64

  public init(seed: UInt64) {
    self.state = seed
  }

  public mutating func nextUInt64() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  public mutating func nextInt(upperBound: Int) -> Int {
    precondition(upperBound > 0)
    // Rejection sampling to avoid modulo bias.
    let bound = UInt64(upperBound)
    let threshold = (UInt64.max - bound &+ 1) % bound
    while true {
      let r = nextUInt64()
      let m = r % bound
      if r &- m >= threshold { return Int(m) }
    }
  }
}
