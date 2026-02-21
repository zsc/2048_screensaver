import AppKit
import CoreGraphics
import Core2048

final class Renderer {
  private struct Palette {
    static let background = NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.11, alpha: 1.0)
    static let board = NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.22, alpha: 1.0)
    static let emptyCell = NSColor(calibratedWhite: 1.0, alpha: 0.06)
    static let textPrimary = NSColor(calibratedWhite: 0.95, alpha: 1.0)
    static let textMuted = NSColor(calibratedWhite: 0.95, alpha: 0.70)
    static let overlay = NSColor(calibratedWhite: 0.0, alpha: 0.35)
  }

  func draw(in bounds: NSRect, state: GameState, isPreview: Bool) {
    guard let cg = NSGraphicsContext.current?.cgContext else { return }

    Palette.background.setFill()
    bounds.fill()

    let headerH = max(28.0, bounds.height * (isPreview ? 0.10 : 0.12))
    let contentRect = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height - headerH)

    let boardSize = max(64.0, min(contentRect.width, contentRect.height) * 0.92)
    let boardRect = NSRect(
      x: contentRect.midX - boardSize / 2,
      y: contentRect.midY - boardSize / 2,
      width: boardSize,
      height: boardSize
    )

    drawHeader(in: NSRect(x: bounds.minX, y: bounds.maxY - headerH, width: bounds.width, height: headerH), state: state)
    drawBoard(cg: cg, rect: boardRect, board: state.board)

    if state.isTerminal {
      drawGameOverOverlay(in: boardRect)
    }
  }

  private func drawHeader(in rect: NSRect, state: GameState) {
    let title = "2048 • Autoplay"
    let score = "Score: \(state.score)"
    let maxE = Board64.maxExponent(state.board)
    let maxTile = (maxE > 0 && maxE < 63) ? (1 << maxE) : 0
    let maxText = maxTile > 0 ? "Max: \(maxTile)" : "Max: —"

    let titleAttrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: max(12, rect.height * 0.42), weight: .semibold),
      .foregroundColor: Palette.textPrimary,
    ]
    let metaAttrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: max(11, rect.height * 0.32), weight: .regular),
      .foregroundColor: Palette.textMuted,
    ]

    let inset = rect.insetBy(dx: 14, dy: 6)
    (title as NSString).draw(at: NSPoint(x: inset.minX, y: inset.midY - 8), withAttributes: titleAttrs)

    let rightText = "\(score)   \(maxText)"
    let size = (rightText as NSString).size(withAttributes: metaAttrs)
    (rightText as NSString).draw(at: NSPoint(x: inset.maxX - size.width, y: inset.midY - 7), withAttributes: metaAttrs)
  }

  private func drawBoard(cg: CGContext, rect: NSRect, board: UInt64) {
    cg.saveGState()
    defer { cg.restoreGState() }

    let corner = rect.width * 0.04
    let boardPath = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    cg.addPath(boardPath)
    cg.setFillColor(Palette.board.cgColor)
    cg.fillPath()

    let gap = max(6.0, rect.width * 0.03)
    let pad = gap
    let cell = (rect.width - pad * 2 - gap * 3) / 4.0

    for r in 0..<4 {
      for c in 0..<4 {
        let x = rect.minX + pad + CGFloat(c) * (cell + gap)
        let y = rect.minY + pad + CGFloat(3 - r) * (cell + gap)
        let cellRect = NSRect(x: x, y: y, width: cell, height: cell)

        let idx = r * 4 + c
        let exp = Board64.getCell(board, index: idx)
        drawTile(in: cellRect, exponent: exp)
      }
    }
  }

  private func drawTile(in rect: NSRect, exponent: UInt8) {
    let corner = rect.width * 0.20
    let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

    let (bg, fg) = tileColors(exponent: exponent)
    bg.setFill()
    path.fill()

    guard exponent > 0 else { return }
    let value = 1 << exponent
    let text = String(value)

    var fontSize = rect.width * 0.36
    if text.count >= 5 { fontSize *= 0.86 }
    if text.count >= 6 { fontSize *= 0.80 }

    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: max(10, fontSize), weight: .heavy),
      .foregroundColor: fg,
    ]

    let size = (text as NSString).size(withAttributes: attrs)
    let p = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
    (text as NSString).draw(at: p, withAttributes: attrs)
  }

  private func tileColors(exponent: UInt8) -> (NSColor, NSColor) {
    if exponent == 0 {
      return (Palette.emptyCell, Palette.textMuted)
    }
    let colors: [NSColor] = [
      NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.96, alpha: 1.0), // 2
      NSColor(calibratedRed: 0.84, green: 0.95, blue: 1.00, alpha: 1.0), // 4
      NSColor(calibratedRed: 0.72, green: 0.90, blue: 1.00, alpha: 1.0), // 8
      NSColor(calibratedRed: 0.60, green: 0.84, blue: 1.00, alpha: 1.0), // 16
      NSColor(calibratedRed: 0.49, green: 0.77, blue: 1.00, alpha: 1.0), // 32
      NSColor(calibratedRed: 0.39, green: 0.70, blue: 1.00, alpha: 1.0), // 64
      NSColor(calibratedRed: 0.30, green: 0.61, blue: 1.00, alpha: 1.0), // 128
      NSColor(calibratedRed: 0.24, green: 0.52, blue: 1.00, alpha: 1.0), // 256
      NSColor(calibratedRed: 0.18, green: 0.42, blue: 1.00, alpha: 1.0), // 512
      NSColor(calibratedRed: 0.13, green: 0.32, blue: 0.98, alpha: 1.0), // 1024
      NSColor(calibratedRed: 0.11, green: 0.23, blue: 0.92, alpha: 1.0), // 2048
      NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.72, alpha: 1.0), // 4096
      NSColor(calibratedRed: 0.20, green: 0.12, blue: 0.56, alpha: 1.0), // 8192
      NSColor(calibratedRed: 0.25, green: 0.08, blue: 0.42, alpha: 1.0), // ...
      NSColor(calibratedRed: 0.30, green: 0.06, blue: 0.32, alpha: 1.0),
    ]
    let idx = max(1, Int(exponent)) - 1
    let bg = colors[min(idx, colors.count - 1)]
    let fg: NSColor = exponent <= 2 ? NSColor(calibratedWhite: 0.14, alpha: 1.0) : NSColor(calibratedWhite: 0.05, alpha: 1.0)
    return (bg, fg)
  }

  private func drawGameOverOverlay(in rect: NSRect) {
    Palette.overlay.setFill()
    rect.fill()

    let text = "Game Over"
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: max(16, rect.width * 0.08), weight: .bold),
      .foregroundColor: Palette.textPrimary,
    ]
    let size = (text as NSString).size(withAttributes: attrs)
    let p = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
    (text as NSString).draw(at: p, withAttributes: attrs)
  }
}
