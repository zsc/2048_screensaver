# CLI Results Report (2026-02-21)

## Environment

- Swift: 6.2.3 (Apple Swift, arm64-apple-macosx26.0)
- Note: this environment’s Command Line Tools SDK does not include `XCTest`, so correctness checks are run via the custom executable `core2048-tests`.

## Correctness / Regression Tests

Command:

```sh
cd Core2048 && swift run -c release core2048-tests
```

Result:

- PASS: `OK (0.78s)`
- Coverage (high level):
  - `UInt64` board encoding round-trips (cell get/set, row encode/decode)
  - `reverseRow` involution for all 65,536 rows
  - `transpose` matches a naive transpose (random boards)
  - Row lookup table correctness: `RowLookup.moveLeftTable` matches a slow reference for all 65,536 rows
  - Full-board move correctness: `Rules.applyMove` matches a slow reference on thousands of random boards
  - Expectimax smoke: terminal handling, determinism on same state, reproducibility (same seed), autoplay terminates

## Baseline AI Gameplay (Average Score)

Command:

```sh
cd Trainer2048 && swift run -c release trainer eval --games 200 --seed 123 --depth 3 --sample 6
```

Settings:

- Weights: built-in baseline (`WeightsIO.makeDefault()`; no `--weights` provided)
- Expectimax: `--depth 3` (plus dynamic deepening in late game), `--sample 6`
- RNG: deterministic per game (seed `123 + gameIndex`)

Results (200 games):

- **avgScore: 26268.0**
- avgMaxExponent: 10.62
- maxTile: 4096 (exponent 12)
- winRate(>=2048): 0.600
- wall time: 11.38s

## Spawn Logic (2/4 tile)

- Empty cell selection: uniform over all empty cells.
- Tile distribution: 2 with probability 0.9 (exponent 1), 4 with probability 0.1 (exponent 2).

## HTML Replay

Command:

```sh
cd Trainer2048 && swift run -c release trainer replay --seed 123 --out ../replay.html
```

Output:

- `replay.html` (self-contained; open in a browser)

## Reproduce

- Tests: `cd Core2048 && swift run -c release core2048-tests`
- Eval baseline: `cd Trainer2048 && swift run -c release trainer eval --games 200 --seed 123 --depth 3 --sample 6`
- Train weights (GA): `cd Trainer2048 && swift run -c release trainer init-config > config.json && swift run -c release trainer train --config config.json --out weights.json`
