---
name: 2048-screensaver-dev
description: 在本仓库开发/调试/发布 2048 自动玩屏保（CLI 优先）：运行 Core2048 correctness 测试、用 trainer eval/train/replay 做评估/训练/回放、构建并安装 macOS `.saver`（含多实例租约 + 自建 timer）。
---

# 2048 自动玩屏保：开发流程（CLI → 屏保）

## 仓库结构速览（改哪里）

- 核心（纯 Swift，无 AppKit 依赖）：`Core2048/Sources/Core2048/`
  - 棋盘编码/位运算：`Board64.swift`
  - 行查表（65536）：`RowLookup.swift`
  - 规则（四向 move、spawn）：`Rules.swift`
  - AI（expectimax + TT + sampling）：`ExpectimaxAI.swift`
  - 评估器/权重 IO：`ValueFunction.swift`
  - 游戏节拍控制：`GameController.swift`
- CLI（评估/GA 训练/HTML 回放）：`Trainer2048/Sources/Trainer2048/`
  - `trainer eval/train/replay`：`TrainerMain.swift`
- GA 对比/复现实验配置：`Trainer2048/ga-report-config.json`
- 屏保（ScreenSaverView + Renderer + lease）：`Screensaver2048/`
  - View 生命周期 + timer + lease：`Screensaver2048/Sources/GameScreenSaverView.swift`
  - 绘制：`Screensaver2048/Sources/Renderer.swift`
  - 资源：`Screensaver2048/Resources/{Info.plist,weights.json}`
- 构建/安装脚本：
  - 构建 `.saver`：`scripts/build_saver.sh`
  - 安装到当前用户：`scripts/install_saver.sh`

## 0) 约束（不要破坏）

- 棋盘必须是单个 `UInt64`，16 个 cell * 4bit（指数 e，row-major，LSB 为 cell0）。
- 随机生成：空格均匀选 1 个位置；2/4 概率为 0.9/0.1（exponent 1/2）。
- Core 必须不依赖 AppKit/ScreenSaver（训练与测试要能跑在 CLI）。

## 1) 开发循环（改 Core/AI/Trainer 时）

1. 跑 Core correctness / regression：
   - `cd Core2048 && swift run -c release core2048-tests`
   - 快速版：`cd Core2048 && swift run -c release core2048-tests --quick`
2. 跑 baseline eval（看平均分/最大块是否退化）：
   - `cd Trainer2048 && swift run -c release trainer eval --games 200 --seed 123 --depth 3 --sample 6`
3. 生成一局 HTML 回放（方便肉眼看策略）：
   - `cd Trainer2048 && swift run -c release trainer replay --seed 123 --out ../replay.html`

提示：
- 当前环境的 Command Line Tools SDK 不包含 `XCTest`，所以测试用自定义 runner：`core2048-tests`。

## 2) 训练权重（GA）

1. 生成默认配置：
   - `cd Trainer2048 && swift run -c release trainer init-config > config.json`
2. 训练输出：
   - `cd Trainer2048 && swift run -c release trainer train --config config.json --out weights.json`
3. 复现评估（同 seed 应稳定）：
   - `cd Trainer2048 && swift run -c release trainer eval --weights weights.json --games 200 --seed 123`
4. 给屏保使用：
   - `cp Trainer2048/weights.json Screensaver2048/Resources/weights.json`
   - 重新构建/安装（见下节）

可选：做“GA 优化前后对比”的可复现实验（用于写报告/回归）：

- 训练（固定参数，输出 `ga-report-weights.json`）：
  - `cd Trainer2048 && swift run -c release trainer train --config ga-report-config.json --out ga-report-weights.json`
- 评估对比（和 baseline 同样 `--games/--seed/--depth/--sample`）：
  - `cd Trainer2048 && swift run -c release trainer eval --games 200 --seed 123 --depth 3 --sample 6`
  - `cd Trainer2048 && swift run -c release trainer eval --weights ga-report-weights.json --games 200 --seed 123 --depth 3 --sample 6`

## 3) 构建 & 安装屏保（.saver）

1. 构建产物：
   - `bash scripts/build_saver.sh`
   - 输出：`Build/Screensaver2048.saver`
2. 安装到当前用户：
   - `bash scripts/install_saver.sh`
   - 安装路径：`~/Library/Screen Savers/Screensaver2048.saver`
3. 启用：
   - 系统设置 → 屏幕保护程序 → 选择 “Screensaver2048” → 预览

常见问题排查：
- 如果提示“不受信任/无法打开”（quarantine）：
  - `xattr -dr com.apple.quarantine "$HOME/Library/Screen Savers/Screensaver2048.saver"`
- 如果预览不刷新：在系统设置里切换到其他屏保再切回来。

## 4) 性能/稳定性原则（屏保侧）

- 不要在 `draw(_:)` 里做搜索；只读 state 绘制。
- 用自建 `DispatchSourceTimer` 推进逻辑 + `setNeedsDisplay` 触发重绘。
- 必须保留 lease 机制，避免系统多实例并行导致 CPU 飙升。

## 5) 屏保“治愈感”调参（速度 + 漂移反弹）

下棋速度（moves/sec）：

- 在 `Screensaver2048/Sources/GameScreenSaverView.swift` 里调 `movesPerSecond`（预览与全屏分别设置）。

棋盘缓慢漂移 + 反弹（扫屏）：

- 逻辑在 `Screensaver2048/Sources/GameScreenSaverView.swift` 的 `updateBoardMotion(...)`：
  - `factor` / `speed` 控制漂移速度（points/sec）
  - `advanceAxis(...)` 控制边界反弹（保持棋盘在 content 区域内）

如果要完全静止（居中不动）：

- 可在 `updateBoardMotion` 里直接把 `boardOrigin = layout.centeredBoardOrigin`，并将 `boardVelocity = .zero`。
