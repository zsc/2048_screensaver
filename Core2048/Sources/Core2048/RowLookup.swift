public struct RowMove: Sendable {
  public let outRow: UInt16
  public let scoreGain: UInt32

  @inlinable
  public init(outRow: UInt16, scoreGain: UInt32) {
    self.outRow = outRow
    self.scoreGain = scoreGain
  }
}

public enum RowLookup {
  public static let moveLeftTable: ContiguousArray<RowMove> = buildMoveLeftTable()

  @inlinable
  public static func moveLeft(row: UInt16) -> RowMove {
    moveLeftTable[Int(row)]
  }

  private static func buildMoveLeftTable() -> ContiguousArray<RowMove> {
    var table = ContiguousArray<RowMove>()
    table.reserveCapacity(65_536)
    for raw in 0..<65_536 {
      let row = UInt16(raw)
      let (outRow, score) = moveRowLeftSlow(row)
      table.append(RowMove(outRow: outRow, scoreGain: score))
    }
    return table
  }

  @inlinable
  static func moveRowLeftSlow(_ row: UInt16) -> (UInt16, UInt32) {
    var tiles: [UInt8] = []
    tiles.reserveCapacity(4)
    tiles.append(UInt8((row >> 0) & 0xF))
    tiles.append(UInt8((row >> 4) & 0xF))
    tiles.append(UInt8((row >> 8) & 0xF))
    tiles.append(UInt8((row >> 12) & 0xF))

    var nonZero: [UInt8] = []
    nonZero.reserveCapacity(4)
    for t in tiles where t != 0 { nonZero.append(t) }

    var merged: [UInt8] = []
    merged.reserveCapacity(4)
    var score: UInt32 = 0
    var i = 0
    while i < nonZero.count {
      let current = nonZero[i]
      if i &+ 1 < nonZero.count, nonZero[i &+ 1] == current {
        let nextExp = min(current &+ 1, 0xF)
        merged.append(nextExp)
        // Score uses the actual merged tile value (may exceed 4-bit exponent, but we clamp exponent storage).
        let scoreExp = UInt32(current) &+ 1
        if scoreExp < 32 {
          score &+= (UInt32(1) << scoreExp)
        }
        i &+= 2
      } else {
        merged.append(current)
        i &+= 1
      }
    }

    while merged.count < 4 { merged.append(0) }
    precondition(merged.count == 4)

    var out: UInt16 = 0
    out |= UInt16(merged[0] & 0xF) << 0
    out |= UInt16(merged[1] & 0xF) << 4
    out |= UInt16(merged[2] & 0xF) << 8
    out |= UInt16(merged[3] & 0xF) << 12

    return (out, score)
  }
}

