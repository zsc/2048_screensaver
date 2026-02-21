public struct TTKey: Hashable, Sendable {
  public let board: UInt64
  public let depth: UInt8
  public let nodeType: UInt8

  @inlinable
  public init(board: UInt64, depth: UInt8, nodeType: UInt8) {
    self.board = board
    self.depth = depth
    self.nodeType = nodeType
  }
}

public struct TranspositionTable: Sendable {
  private var storage: [TTKey: Double]
  public let capacity: Int

  public init(capacity: Int) {
    self.capacity = max(0, capacity)
    self.storage = [:]
    if self.capacity > 0 { self.storage.reserveCapacity(self.capacity) }
  }

  public mutating func value(for key: TTKey) -> Double? {
    storage[key]
  }

  public mutating func store(_ value: Double, for key: TTKey) {
    guard capacity > 0 else { return }
    if storage.count >= capacity {
      storage.removeAll(keepingCapacity: true)
    }
    storage[key] = value
  }

  public mutating func reset() {
    storage.removeAll(keepingCapacity: true)
  }
}
