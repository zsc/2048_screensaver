import Foundation
import Core2048

struct ReplayFrame: Codable, Sendable {
  var step: Int
  var move: String?
  var score: UInt64
  var scoreGain: UInt32?
  var spawnedIndex: Int?
  var spawnedExponent: UInt8?
  var maxExponent: UInt8
  var emptyCount: Int
  var cells: [UInt8] // 16 exponents, row-major
}

enum Replay {
  static func runOneGameHTML(
    weights: Weights,
    seed: UInt64,
    depth: Int,
    sample: Int,
    maxSteps: Int
  ) throws -> String {
    let evaluator = LinearValueFunction(weights: weights)
    let ai = ExpectimaxAI(evaluator: evaluator, config: .init(maxDepth: depth, sampleEmptyK: sample, ttCapacity: 200_000))

    var state = GameState.newGame(seed: seed)
    var frames: [ReplayFrame] = []
    frames.reserveCapacity(4096)

    frames.append(makeFrame(step: 0, move: nil, score: state.score, scoreGain: nil, spawned: nil, board: state.board))

    var step = 0
    while !state.isTerminal {
      step &+= 1
      if step > maxSteps { break }
      guard let mv = ai.chooseMove(state: state) else { break }

      guard let res = Rules.applyMove(board: state.board, move: mv) else {
        // Should never happen if AI is correct.
        break
      }
      state.board = res.board
      state.score &+= UInt64(res.scoreGain)

      let spawned = spawnRandomDetailed(board: state.board, rng: &state.rng)
      if let spawned {
        state.board = spawned.board
      }

      frames.append(
        makeFrame(
          step: step,
          move: mv.rawValue,
          score: state.score,
          scoreGain: res.scoreGain,
          spawned: spawned.map { ($0.index, $0.exponent) },
          board: state.board
        )
      )
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let json = try String(data: encoder.encode(frames), encoding: .utf8) ?? "[]"

    return htmlDocument(framesJSON: json, seed: seed, depth: depth, sample: sample, maxSteps: maxSteps)
  }

  private static func makeFrame(
    step: Int,
    move: String?,
    score: UInt64,
    scoreGain: UInt32?,
    spawned: (Int, UInt8)?,
    board: UInt64
  ) -> ReplayFrame {
    var cells: [UInt8] = []
    cells.reserveCapacity(16)
    for i in 0..<16 { cells.append(Board64.getCell(board, index: i)) }
    return ReplayFrame(
      step: step,
      move: move,
      score: score,
      scoreGain: scoreGain,
      spawnedIndex: spawned?.0,
      spawnedExponent: spawned?.1,
      maxExponent: Board64.maxExponent(board),
      emptyCount: Board64.emptyCount(board),
      cells: cells
    )
  }

  private static func spawnRandomDetailed(
    board: UInt64,
    rng: inout SplitMix64
  ) -> (board: UInt64, index: Int, exponent: UInt8)? {
    let empties = Rules.emptyCells(board: board)
    guard !empties.isEmpty else { return nil }
    let index = empties[rng.nextInt(upperBound: empties.count)]
    let exponent: UInt8 = (rng.nextInt(upperBound: 10) == 0) ? 2 : 1
    let out = Rules.spawn(board: board, index: index, exponent: exponent)
    return (out, index, exponent)
  }

  private static func htmlDocument(framesJSON: String, seed: UInt64, depth: Int, sample: Int, maxSteps: Int) -> String {
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>2048 Replay</title>
        <style>
          :root {
            --bg: #0b0f14;
            --panel: #121a24;
            --grid: #1d2a3a;
            --cell: rgba(255,255,255,0.06);
            --text: #e8eef6;
            --muted: rgba(232,238,246,0.70);
            --accent: #7cc5ff;
            --shadow: rgba(0,0,0,0.35);
          }
          body {
            margin: 0;
            font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, "Apple Color Emoji", "Segoe UI Emoji";
            background: radial-gradient(1200px 600px at 30% -10%, #1a2330 0%, var(--bg) 55%), var(--bg);
            color: var(--text);
          }
          .wrap {
            max-width: 980px;
            margin: 24px auto;
            padding: 0 16px 40px;
          }
          .header {
            display: grid;
            grid-template-columns: 1fr auto;
            gap: 16px;
            align-items: center;
            margin-bottom: 16px;
          }
          h1 {
            font-size: 18px;
            margin: 0;
            letter-spacing: 0.2px;
            font-weight: 650;
          }
          .meta {
            font-size: 12px;
            color: var(--muted);
            margin-top: 6px;
            line-height: 1.4;
          }
          .panel {
            background: linear-gradient(180deg, rgba(255,255,255,0.06), rgba(255,255,255,0.03));
            border: 1px solid rgba(255,255,255,0.10);
            border-radius: 14px;
            box-shadow: 0 18px 45px var(--shadow);
            overflow: hidden;
          }
          .content {
            display: grid;
            grid-template-columns: 420px 1fr;
            gap: 18px;
            padding: 18px;
          }
          @media (max-width: 860px) {
            .content { grid-template-columns: 1fr; }
          }
          .board {
            width: 420px;
            height: 420px;
            border-radius: 18px;
            background: var(--grid);
            padding: 12px;
            box-sizing: border-box;
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            grid-template-rows: repeat(4, 1fr);
            gap: 12px;
          }
          @media (max-width: 860px) {
            .board { width: 100%; aspect-ratio: 1 / 1; height: auto; }
          }
          .tile {
            border-radius: 14px;
            background: var(--cell);
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: 800;
            font-size: 28px;
            letter-spacing: 0.3px;
            user-select: none;
            transition: transform 120ms ease, background 120ms ease, color 120ms ease;
          }
          .tile.small { font-size: 22px; }
          .tile.tiny { font-size: 18px; }
          .controls {
            display: grid;
            gap: 12px;
          }
          .row {
            display: grid;
            grid-template-columns: auto 1fr auto;
            gap: 10px;
            align-items: center;
          }
          button {
            background: rgba(124,197,255,0.12);
            border: 1px solid rgba(124,197,255,0.25);
            color: var(--text);
            padding: 10px 12px;
            border-radius: 12px;
            font-weight: 650;
            cursor: pointer;
          }
          button:hover { border-color: rgba(124,197,255,0.45); }
          button:active { transform: translateY(1px); }
          input[type="range"] { width: 100%; }
          select {
            width: 100%;
            background: rgba(255,255,255,0.06);
            border: 1px solid rgba(255,255,255,0.14);
            color: var(--text);
            padding: 10px 12px;
            border-radius: 12px;
          }
          .stats {
            display: grid;
            gap: 10px;
            background: rgba(0,0,0,0.18);
            border: 1px solid rgba(255,255,255,0.10);
            border-radius: 14px;
            padding: 12px;
          }
          .kv {
            display: grid;
            grid-template-columns: 140px 1fr;
            gap: 10px;
            font-size: 13px;
            line-height: 1.4;
          }
          .kv .k { color: var(--muted); }
          .kv .v { font-variant-numeric: tabular-nums; }
          .footer {
            padding: 12px 18px 18px;
            color: var(--muted);
            font-size: 12px;
          }
          a { color: var(--accent); text-decoration: none; }
          a:hover { text-decoration: underline; }
        </style>
      </head>
      <body>
        <div class="wrap">
          <div class="header">
            <div>
              <h1>2048 Replay</h1>
              <div class="meta">seed: \(seed) • depth: \(depth) • sample: \(sample) • maxSteps: \(maxSteps)</div>
            </div>
            <div class="meta" id="frameSummary"></div>
          </div>

          <div class="panel">
            <div class="content">
              <div class="board" id="board"></div>

              <div class="controls">
                <div class="row">
                  <button id="prevBtn" title="Previous (←)">◀</button>
                  <input id="scrub" type="range" min="0" max="0" value="0" />
                  <button id="nextBtn" title="Next (→)">▶</button>
                </div>

                <div class="row" style="grid-template-columns: auto auto 1fr;">
                  <button id="playBtn">Play</button>
                  <button id="pauseBtn">Pause</button>
                  <select id="speed">
                    <option value="1">1×</option>
                    <option value="2" selected>2×</option>
                    <option value="4">4×</option>
                    <option value="8">8×</option>
                    <option value="16">16×</option>
                  </select>
                </div>

                <div class="stats" id="stats"></div>
              </div>
            </div>

            <div class="footer">
              Controls: ←/→ step • Space play/pause • Home/End jump
            </div>
          </div>
        </div>

        <script id="replay-data" type="application/json">\(framesJSON)</script>
        <script>
          const frames = JSON.parse(document.getElementById('replay-data').textContent);
          const boardEl = document.getElementById('board');
          const statsEl = document.getElementById('stats');
          const frameSummaryEl = document.getElementById('frameSummary');
          const scrub = document.getElementById('scrub');
          const prevBtn = document.getElementById('prevBtn');
          const nextBtn = document.getElementById('nextBtn');
          const playBtn = document.getElementById('playBtn');
          const pauseBtn = document.getElementById('pauseBtn');
          const speedSel = document.getElementById('speed');

          scrub.max = Math.max(0, frames.length - 1);

          function tileColor(exp) {
            if (exp === 0) return { bg: 'rgba(255,255,255,0.06)', fg: 'rgba(232,238,246,0.45)' };
            const palette = [
              '#e9eef6','#d7f3ff','#bde6ff','#9cd6ff','#7cc5ff','#63b2ff','#4b9dff',
              '#3b85ff','#2d6bff','#2452ff','#1b3aff','#2d29b7','#3a1b90','#4a136c','#5b0d4c'
            ];
            const idx = Math.min(exp, palette.length - 1);
            const bg = palette[idx];
            const fg = exp <= 2 ? '#18212b' : '#06111b';
            return { bg, fg };
          }

          function tileText(exp) {
            if (exp === 0) return '';
            // exp is small (<= 15); safe.
            return String(1 << exp);
          }

          function render(frameIndex) {
            const f = frames[frameIndex];
            frameSummaryEl.textContent = `frame ${frameIndex}/${frames.length - 1}`;

            if (boardEl.childElementCount !== 16) {
              boardEl.innerHTML = '';
              for (let i = 0; i < 16; i++) {
                const d = document.createElement('div');
                d.className = 'tile';
                boardEl.appendChild(d);
              }
            }

            for (let i = 0; i < 16; i++) {
              const exp = f.cells[i];
              const el = boardEl.children[i];
              const c = tileColor(exp);
              el.style.background = c.bg;
              el.style.color = c.fg;
              const text = tileText(exp);
              el.textContent = text;
              el.classList.toggle('small', text.length >= 5);
              el.classList.toggle('tiny', text.length >= 6);
            }

            const spawned = (f.spawnedIndex != null && f.spawnedExponent != null)
              ? `idx ${f.spawnedIndex} (exp ${f.spawnedExponent}, ${1 << f.spawnedExponent})`
              : '—';
            const lastMove = f.move ?? '—';
            const gain = (f.scoreGain != null) ? `+${f.scoreGain}` : '—';

            statsEl.innerHTML = `
              <div class="kv"><div class="k">Step</div><div class="v">${f.step}</div></div>
              <div class="kv"><div class="k">Score</div><div class="v">${f.score}</div></div>
              <div class="kv"><div class="k">Move</div><div class="v">${lastMove}</div></div>
              <div class="kv"><div class="k">Score gain</div><div class="v">${gain}</div></div>
              <div class="kv"><div class="k">Spawned</div><div class="v">${spawned}</div></div>
              <div class="kv"><div class="k">Max tile</div><div class="v">${1 << f.maxExponent} (exp ${f.maxExponent})</div></div>
              <div class="kv"><div class="k">Empty cells</div><div class="v">${f.emptyCount}</div></div>
            `;
          }

          let idx = 0;
          let timer = null;
          let baseDelayMs = 400; // 1× speed

          function setIdx(n) {
            idx = Math.max(0, Math.min(frames.length - 1, n));
            scrub.value = String(idx);
            render(idx);
          }

          function currentSpeed() {
            const s = Number(speedSel.value);
            return (Number.isFinite(s) && s > 0) ? s : 1;
          }

          function currentDelayMs() {
            return Math.max(10, Math.round(baseDelayMs / currentSpeed()));
          }

          function play() {
            if (timer != null) return;
            const loop = () => {
              if (idx >= frames.length - 1) { pause(); return; }
              setIdx(idx + 1);
              timer = setTimeout(loop, currentDelayMs());
            };
            timer = setTimeout(loop, currentDelayMs());
          }

          function pause() {
            if (timer != null) clearTimeout(timer);
            timer = null;
          }

          scrub.addEventListener('input', (e) => setIdx(Number(e.target.value)));
          prevBtn.addEventListener('click', () => setIdx(idx - 1));
          nextBtn.addEventListener('click', () => setIdx(idx + 1));
          playBtn.addEventListener('click', play);
          pauseBtn.addEventListener('click', pause);
          speedSel.addEventListener('change', () => {
            // Apply new delay immediately if currently playing.
            if (timer != null) {
              pause();
              play();
            }
          });

          window.addEventListener('keydown', (e) => {
            if (e.key === 'ArrowLeft') { e.preventDefault(); pause(); setIdx(idx - 1); }
            else if (e.key === 'ArrowRight') { e.preventDefault(); pause(); setIdx(idx + 1); }
            else if (e.key === 'Home') { e.preventDefault(); pause(); setIdx(0); }
            else if (e.key === 'End') { e.preventDefault(); pause(); setIdx(frames.length - 1); }
            else if (e.key === ' ') { e.preventDefault(); (timer ? pause() : play()); }
          });

          setIdx(0);
        </script>
      </body>
    </html>
    """
  }
}
