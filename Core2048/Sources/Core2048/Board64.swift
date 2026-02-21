public enum Board64 {
  @inlinable
  public static func getCell(_ board: UInt64, index: Int) -> UInt8 {
    precondition(index >= 0 && index < 16)
    return UInt8((board >> (UInt64(index) &* 4)) & 0xF)
  }

  @inlinable
  public static func setCell(_ board: UInt64, index: Int, exponent: UInt8) -> UInt64 {
    precondition(index >= 0 && index < 16)
    precondition(exponent <= 0xF)
    let shift = UInt64(index) &* 4
    let clearMask = ~(UInt64(0xF) << shift)
    let cleared = board & clearMask
    return cleared | (UInt64(exponent) << shift)
  }

  @inlinable
  public static func encodeRow(_ board: UInt64, rowIndex: Int) -> UInt16 {
    precondition(rowIndex >= 0 && rowIndex < 4)
    return UInt16((board >> (UInt64(rowIndex) &* 16)) & 0xFFFF)
  }

  @inlinable
  public static func decodeRow(_ row: UInt16, rowIndex: Int) -> UInt64 {
    precondition(rowIndex >= 0 && rowIndex < 4)
    return UInt64(row) << (UInt64(rowIndex) &* 16)
  }

  @inlinable
  public static func reverseRow(_ row: UInt16) -> UInt16 {
    let a = (row & 0x000F) << 12
    let b = (row & 0x00F0) << 4
    let c = (row & 0x0F00) >> 4
    let d = (row & 0xF000) >> 12
    return a | b | c | d
  }

  @inlinable
  public static func transpose(_ board: UInt64) -> UInt64 {
    // Standard 4x4 nibble transpose used by many 2048 engines.
    let a1 = board & 0xF0F0_0F0F_F0F0_0F0F
    let a2 = board & 0x0000_F0F0_0000_F0F0
    let a3 = board & 0x0F0F_0000_0F0F_0000
    let a = a1 | (a2 << 12) | (a3 >> 12)
    let b1 = a & 0xFF00_FF00_00FF_00FF
    let b2 = a & 0x00FF_00FF_0000_0000
    let b3 = a & 0x0000_0000_FF00_FF00
    return b1 | (b2 >> 24) | (b3 << 24)
  }

  @inlinable
  public static func maxExponent(_ board: UInt64) -> UInt8 {
    var maxE: UInt8 = 0
    var b = board
    for _ in 0..<16 {
      let e = UInt8(b & 0xF)
      if e > maxE { maxE = e }
      b >>= 4
    }
    return maxE
  }

  @inlinable
  public static func emptyCount(_ board: UInt64) -> Int {
    var count = 0
    var b = board
    for _ in 0..<16 {
      if (b & 0xF) == 0 { count &+= 1 }
      b >>= 4
    }
    return count
  }

  @inlinable
  public static func prettyDescription(_ board: UInt64) -> String {
    var lines: [String] = []
    lines.reserveCapacity(4)
    for r in 0..<4 {
      var parts: [String] = []
      parts.reserveCapacity(4)
      for c in 0..<4 {
        let idx = r * 4 + c
        let e = getCell(board, index: idx)
        if e == 0 {
          parts.append(".")
        } else {
          parts.append(String(1 << e))
        }
      }
      lines.append(parts.joined(separator: "\t"))
    }
    return lines.joined(separator: "\n")
  }
}

