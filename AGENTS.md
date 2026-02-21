# SPEC：2048 Autoplay macOS 屏保（Expectimax + GA 优化 Value Function，64-bit 棋盘）

> 目标读者：用 gemini-cli / codex 直接生成代码与工程结构
> 语言建议：Swift（屏保 View & 运行时），Swift（训练 CLI）或 Swift + Python（可选）
> 关键约束：棋盘用 **一个 `UInt64`** 表示；AI 用 **expectimax + value function**；value function 参数 **离线用遗传算法（GA）优化**。

---

## 1. 项目概述

实现一个 macOS 屏保（`.saver` bundle），在全屏/预览中持续渲染 2048 游戏过程，并由 AI 自动下棋。AI 核心在运行时只做：

* 规则模拟（64-bit board + 查表 move）
* expectimax 搜索（深度受限 + 缓存/采样优化）
* 叶子结点评估（value function：特征提取 + 权重线性组合）

value function 的权重由离线训练工具通过 GA 优化得到，作为资源随屏保一起分发（例如 `weights.json`）。

---

## 2. 主要难点（必须在设计阶段解决）

### 2.1 2048 AI（运行时）主要难点

1. **正确且极快的 move 生成**：
   64-bit 棋盘的位运算 + 65536 行查表（row lookup）是高性能 expectimax 的基础。任何 move 规则 bug 会直接污染训练与推理结果。
2. **expectimax 的分支爆炸**：
   chance 节点要枚举空格并插入 2/4（通常 0.9/0.1），分支数随空格数上升；必须做：缓存、空格采样、动态深度等。
3. **value function 特征要“可优化且可泛化”**：
   GA 只能优化你提供的参数空间；特征设计太弱 → AI 上限低；特征太贵 → 推理太慢；特征太多 → GA 搜索空间爆炸。
4. **可重复性（reproducibility）**：
   训练评估必须可复现：固定 RNG、固定 seeds、固定深度/采样策略，否则 GA 适应的是噪声。

### 2.2 macOS 屏保（View & 生命周期）主要难点

1. **ScreenSaverView 生命周期与回调不可靠**：
   实践经验显示系统在新版本 macOS 上存在“`stopAnimation` 不按文档时机调用”“重复创建实例导致多个实例并行运行”等问题，需要工程化规避（例如自建 timer、实例租约机制）。([Michael Tsai][1])
2. **渲染与 AI 步进的解耦**：
   屏保通常 30fps/60fps 重绘，但 AI 不应每帧都做深度搜索，否则 CPU 飙升。需要逻辑步进频率（moves/sec）与渲染帧率分离。
3. **预览（System Settings）与全屏行为差异**：
   `isPreview`、预览缩略图、Options 按钮等行为在不同 macOS/Xcode 组合下可能异常，需要测试与降级策略。([zsmb.co][2])

---

## 3. 范围定义

### 3.1 Goals（必须实现）

* ✅ 2048 规则引擎：`UInt64` 棋盘表示、四向移动、合并与得分、随机生成新 tile
* ✅ AI：expectimax + value function（权重从资源加载）
* ✅ 离线训练：GA 优化 value function 权重；输出 `weights.json`
* ✅ macOS 屏保：`.saver` bundle；预览与全屏可运行；持续自动玩并渲染
* ✅ MVC 架构：Model/AI/Controller 与 View 解耦，核心逻辑可在 CLI 中复用

### 3.2 Non-goals（明确不做）

* ❌ 不做在线学习（运行时不训练）
* ❌ 不做联网/排行/上传
* ❌ 不追求“最强 2048 SOTA”；追求可维护与观感稳定
* ❌ 不实现复杂 UI 编辑器（最多一个简单 Options/配置面板）

---

## 4. 总体架构（MVC）

### 4.1 模块划分

**Core（纯 Swift，无 AppKit 依赖）**

* `Model`

  * `Board64`（`UInt64` + 辅助函数）
  * `GameState`（board、score、rngState、isGameOver）
  * `Move` / `MoveResult`
  * `Rules`（applyMove、spawnTile、legalMoves、terminal）
* `AI`

  * `ExpectimaxSearch`
  * `ValueFunction`（特征提取 + 权重）
  * `TranspositionTable`（缓存）
* `Controller`

  * `GameController`（step/reset、节拍控制、策略参数）

**Trainer（离线训练 CLI，可复用 Core）**

* `GATrainer`（population、mutation、selection、fitness eval）
* `EvaluatorRunner`（批量跑局、统计指标、可复现 seeds）

**ScreensaverApp（View 层）**

* `GameScreenSaverView : ScreenSaverView`（或等价）
* `Renderer`（CoreGraphics/AppKit 绘制 board、tile、分数、状态）
* `Settings`（可选配置面板 + defaults）

### 4.2 依赖规则

* `ScreensaverApp` 依赖 `Core`
* `Trainer` 依赖 `Core`
* `Core` 不依赖 AppKit / ScreenSaver.framework（确保训练与测试可在 CLI 运行）

---

## 5. 2048 核心数据结构（64-bit 棋盘）

### 5.1 Board 编码（必须固定并写入文档/测试）

* `board: UInt64`
* 16 个 cell，每个 cell 用 4 bits（nibble）存储 **指数** `e`：

  * `e = 0`：空
  * `e = 1`：2
  * `e = 2`：4
  * …
  * tile 值 `value = 1 << e`（当 e>0）
* cell 顺序：**row-major，从左上到右下**
  `index = row*4 + col`，row/col ∈ [0,3]
* bit 布局：cell0 放在最低 4 bits（LSB nibble）
  `cell(i)` 位于 `board >> (4*i) & 0xF`

### 5.2 必须提供的 Board API（Core）

* `getCell(board, idx) -> UInt8`
* `setCell(board, idx, e) -> UInt64`（或 inout）
* `encodeRow(board, rowIndex) -> UInt16`（4 nibbles）
* `decodeRow(row16, rowIndex) -> UInt64RowMask`（用于组装）
* `transpose(board) -> UInt64`（4x4 转置）
* `reverseRow(row16) -> UInt16`（nibble 顺序反转）

---

## 6. Move 生成（高性能：行查表）

### 6.1 Row 查表（必须实现）

构建 `RowMoveLeft[65536]`，输入为一个 `UInt16`（4 nibbles），输出包含：

* `outRow: UInt16`
* `scoreGain: UInt32`（本次合并产生的分数增量）
* `moved: Bool`（是否发生变化）

> 这是性能关键点：expectimax 会大量调用 move；必须避免逐格数组操作。

### 6.2 行左移规则（标准 2048）

对 4 个格子：

1. 去掉空格压缩
2. 从左到右合并相邻相同指数（每个 tile 每次 move 最多参与一次合并）
3. 再压缩补空

### 6.3 四向 move（必须用查表组装）

* Left：对每一行 `encodeRow` → 查表 → 拼回 board
* Right：`reverseRow` + Left 查表 + reverse 回来
* Up/Down：`transpose(board)` 后做 Left/Right，再 transpose 回来

### 6.4 规则引擎必须提供

* `applyMove(state, move) -> newState?`

  * 若 move 不改变 board：返回 nil（非法 move）
* `legalMoves(state) -> [Move]`
* `isTerminal(state) -> Bool`（无合法 move）

---

## 7. Chance：随机生成 tile（运行时规则 + expectimax chance 节点）

### 7.1 生成规则（标准 2048）

* 在所有空格中 **均匀** 选 1 个位置
* 生成 tile：

  * 2 的概率 0.9（指数=1）
  * 4 的概率 0.1（指数=2）

### 7.2 必须实现的 API

* `emptyCells(board) -> [Int]`（idx 列表）
* `spawn(board, idx, exponent) -> UInt64`
* `spawnRandom(state, rng) -> state`

---

## 8. Value Function（运行时评估器）

### 8.1 形式（建议：线性模型，GA 易优化）

`V(board) = Σ (w_i * f_i(board))`

要求：

* 特征 `f_i(board)` 必须计算足够快（尽量只看相邻/行列、配合查表）
* `weights.json` 可热加载（屏保启动时加载一次即可）

### 8.2 推荐特征集合（默认实现）

至少实现以下特征（可扩展）：

1. `f_empty`: 空格数（越多越好）
2. `f_max`: 最大指数（越大越好）
3. `f_smooth`: 相邻格（上下左右）指数差的负和（越平滑越好）
4. `f_mono`: 行/列的单调性（越单调越好，鼓励梯度）
5. `f_mergePotential`: 相邻相同指数对数（越多越好）
6. `f_cornerMax`: max tile 在角落加分（稳定策略）

> 这些特征是经典启发式组合，GA 优化权重时更稳定。

### 8.3 运行时接口（Core）

* `struct Weights { version, createdAt, params: [String: Double] }`
* `protocol BoardEvaluator { func evaluate(board: UInt64) -> Double }`
* `final class LinearValueFunction: BoardEvaluator`

  * `init(weights: Weights)`
  * `evaluate(board)`

---

## 9. Expectimax（运行时 AI）

### 9.1 节点定义

* **MAX 节点**（玩家选择 move）：
  `value = max_{move∈legal} Q(move)`
* **CHANCE 节点**（随机插入 tile）：
  `value = E_{cell∈empty}[ 0.9*V(insert 2) + 0.1*V(insert 4) ]`

### 9.2 叶子结点

满足任一条件则返回：

* `depth == 0`
* `terminal(board) == true`

叶子返回：

* `evaluate(board)`（可选：加上累计分数或折扣项）

### 9.3 必须实现的优化

1. **Transposition Table（缓存）**

   * key 至少包含：`board + depth + nodeType`
   * value：`Double`
2. **动态深度 / 空格采样**

   * 若 `emptyCount` 很大：chance 节点只采样 K 个空格（例如 K=4~8），并按比例估计期望
   * 若 `emptyCount` 很小：可加深搜索
3. **Move ordering（可选但建议）**

   * 根据简单启发式（如 `f_empty`、`f_mono`）对 moves 排序，便于更快收敛（即使没有 alpha-beta，也能减少缓存未命中成本）

### 9.4 伪代码（实现参考）

```text
expectimax(board, depth, nodeType):
  if depth == 0 or noMoves(board): return Eval(board)

  key = (board, depth, nodeType)
  if TT has key: return TT[key]

  if nodeType == MAX:
     best = -INF
     for move in legalMoves(board):
        (b2, gain) = applyMove(board, move)
        if b2 == board: continue
        v = gain + expectimaxChance(b2, depth-1)
        best = max(best, v)
     TT[key] = best
     return best

  if nodeType == CHANCE:
     empties = emptyCells(board)
     S = maybeSample(empties)
     acc = 0
     for idx in S:
        b2 = spawn(board, idx, 1)   // 2
        b4 = spawn(board, idx, 2)   // 4
        acc += 0.9 * expectimax(b2, depth-1, MAX)
        acc += 0.1 * expectimax(b4, depth-1, MAX)
     acc /= len(S)
     TT[key] = acc
     return acc
```

### 9.5 AI 对外接口（Core）

* `enum Move { up, down, left, right }`
* `protocol AIPlayer { func chooseMove(state: GameState) -> Move? }`
* `final class ExpectimaxAI: AIPlayer`

  * 参数：`maxDepth`, `sampleEmptyK`, `ttCapacity`, `rngSeedPolicy`

---

## 10. 离线训练：遗传算法（GA）

### 10.1 训练目标（fitness）

fitness 建议组合：

* `avgScore`（平均分）
* `avgMaxTileExponent`（平均最大块）
* （可选）`winRate(>=2048)` 或达到某阈值的比例

示例：
`fitness = avgScore + A * avgMaxTileExponent`

### 10.2 可重复性要求（必须）

* Trainer 支持指定 `--seed`
* 每个 genome 的评估使用固定 seeds 序列（例如 `seed + genomeIndex*1_000_000 + gameIndex`）
* 固定 expectimax 参数（深度、采样策略）用于训练，避免环境漂移

### 10.3 GA 机制（必须实现）

* `populationSize`（如 64~256）
* `elitism`（保留 top E）
* `selection`：tournament 或 rank selection
* `crossover`：uniform / blend（BLX-α）
* `mutation`：高斯噪声 + clip 到范围
* `generations`：N 代
* 并行评估：按 CPU 核数并行跑对局（要求线程安全 RNG）

### 10.4 Trainer CLI（必须）

提供可执行命令（示例接口）：

* `trainer init-config > config.json`
* `trainer train --config config.json --out weights.json`
* `trainer eval --weights weights.json --games 200 --seed 123 --report out.csv`

输出：

* `weights.json`（含版本号、特征名、权重、训练参数摘要、时间戳）
* （可选）每代日志 CSV（best/mean/std）

---

## 11. View 层与 macOS 屏保适配

> 本节重点是：**如何在 ScreenSaverView 的不稳定生命周期里稳定跑 AI + 渲染**。

### 11.1 技术基础（必须遵循）

* 屏保用 `ScreenSaverView` 子类实现；可以选择在 `drawRect` 绘制，并在动画 tick 里 `setNeedsDisplay(true)` 来触发重绘。([Leopard ADC][3])
* 屏保以 `.saver` bundle 形式分发，通常位于 `~/Library/Screen Savers` 或系统 Library 的对应目录。([Leopard ADC][3])
* Xcode 新建项目可用 Screen Saver 模板（默认给 Objective-C），可迁移/重写为 Swift。([zsmb.co][2])

### 11.2 生命周期/计时策略（关键要求）

已知在部分 macOS 版本上：

* `stopAnimation` 可能只在预览缩略图流程中触发，而非正常退出时触发；
* 系统可能反复创建新的 `ScreenSaverView` 实例而旧实例未消失，导致多个实例并行“活着”。([Michael Tsai][1])

因此必须实现：

1. **自建逻辑 Timer（不要只依赖 animateOneFrame）**

   * 在 `startAnimation()` 或 `viewDidMoveToWindow()` 启动 `Timer` / `DispatchSourceTimer`
   * tick 里做：`controller.stepIfNeeded()` + `needsDisplay`
2. **实例租约（Lease）机制，避免多实例并行消耗 CPU**

   * 全局 `ActiveInstanceToken`（自增整数）
   * 每个 view 启动时抢占 token，tick 时若 token 不匹配则直接 return（不再推进 AI）
3. **尽量低资源：不创建后台线程常驻、不做高频深度搜索**

   * 因为屏保进程可能长期不退出（即使屏保停止）。([Michael Tsai][1])

### 11.3 渲染（Renderer 需求）

* 使用 AppKit/CoreGraphics 绘制（`NSBezierPath`/`CGContext`）：

  * 背景
  * 4x4 网格
  * tile：圆角矩形 + 文本（2/4/8…）
  * score / 最大块（可选）
* 自适应：

  * 预览窗口很小：字体与间距按比例缩放
  * 全屏：居中显示，可加淡入/动画（可选）

### 11.4 控制器与渲染解耦（必须）

* `Renderer` 只读 `GameState`，不调用 AI
* `GameController` 管理逻辑节拍：

  * 参数：`movesPerSecond`（例如 5~20）
  * 参数：`maxSearchDepth`（例如 3~5，或动态）
  * 每次 step：AI 选 move → applyMove → spawnRandom → 更新 state
  * game over：等待 N 秒 → reset

### 11.5 调试/开发体验（强烈建议）

增加一个 **SaverTest 宿主 App target**：不需要安装屏保也能运行 view，便于调试与性能分析。([GitHub][4])

### 11.6 分发（可选，但建议写入工程脚本）

若要给他人安装，需要签名与公证（notarization）流程；可以在 `README` 给出步骤。([Gabriel Uribe][5])

---

## 12. 仓库结构（建议）

```text
2048-screensaver/
  README.md
  SPEC.md

  Core2048/
    Package.swift
    Sources/
      Core2048/
        Board64.swift
        RowLookup.swift
        Rules.swift
        GameState.swift
        ValueFunction.swift
        ExpectimaxAI.swift
        TranspositionTable.swift
        RNG.swift
    Tests/
      Core2048Tests/
        BoardEncodingTests.swift
        MoveRulesTests.swift
        RowLookupTests.swift
        ExpectimaxSmokeTests.swift

  Trainer2048/
    Package.swift
    Sources/
      Trainer2048/
        main.swift
        GAConfig.swift
        GAEngine.swift
        FitnessEval.swift
        ReportWriter.swift

  Screensaver2048.xcodeproj/
    Screensaver2048/              # .saver target
      GameScreenSaverView.swift
      Renderer.swift
      Resources/
        weights.json              # 默认权重
        Fonts/ (optional)
    SaverTestApp/                 # host app target
      AppDelegate.swift
      WindowController.swift
```

---

## 13. 验收标准（Acceptance Criteria）

### 13.1 Core / Rules

* ✅ `applyMove` 与标准 2048 行为一致（含“每格每步最多合并一次”）
* ✅ `RowMoveLeft` 查表覆盖 0..65535 所有行编码且通过单元测试
* ✅ 1000 局随机模拟无崩溃、无非法状态（指数溢出/负分等）

### 13.2 AI

* ✅ AI 永远只返回合法 move（或在 terminal 返回 nil）
* ✅ 设定参数下（例如 depth=3，适度采样）能稳定运行且每步耗时可控（例如 < 30ms 的量级，具体可调）

### 13.3 Trainer

* ✅ `trainer train` 能产出 `weights.json`
* ✅ `trainer eval` 可复现（同 seed 输出同统计）
* ✅ 训练日志包含每代 best/mean 等指标

### 13.4 Screensaver

* ✅ 预览可见且能自动玩（必要时可通过重新选中屏保触发预览刷新作为 workaround）([zsmb.co][2])
* ✅ 全屏屏保可持续运行，不出现明显卡死/CPU 飙升
* ✅ 多实例问题被“租约机制”抑制：即便系统创建多个实例，也只有最新实例推进逻辑([Michael Tsai][1])

---

## 14. 里程碑（实现顺序建议）

1. **M1：Core 规则引擎 + 64-bit 编码 + Row 查表 + 单测**
2. **M2：ValueFunction（特征 + weights.json 读取）**
3. **M3：ExpectimaxAI（含缓存/采样/动态深度）+ 冒烟测试**
4. **M4：Trainer CLI（GA）+ eval/报告输出**
5. **M5：Screensaver View（渲染 + Timer + 租约机制）**
6. **M6：SaverTest host app + 性能调参 + 可选配置面板/分发脚本**

---

## 15. 实现备注（给 codex/gemini-cli 的“坑位提示”）

* **性能优先级**：Row 查表 > transpose/bit ops > 特征提取查表化 > expectimax 缓存命中
* **训练噪声控制**：训练时固定 expectimax 参数、固定 seeds、固定采样策略
* **屏保生命周期**：不要假设 `stopAnimation` 一定会在退出时调用；用租约机制 + 低资源自保([Michael Tsai][1])
* **工程模板**：Xcode Screen Saver 模板默认 ObjC，Swift 可用但需要手动整理工程与桥接/删除 ObjC 文件([zsmb.co][2])

---

如果你希望我把这份 SPEC 再“压缩成一页（适合直接当 prompt）”或“拆成 TODO checklist（逐条可执行）”，我也可以直接给两个版本。

[1]: https://mjtsai.com/blog/2025/12/10/how-to-make-a-macos-screen-saver/ "Michael Tsai - Blog  -  How to Make a macOS Screen Saver"
[2]: https://zsmb.co/building-a-macos-screen-saver-in-kotlin/ "Building a macOS screen saver in Kotlin - zsmb.co"
[3]: https://leopard-adc.pepas.com/documentation/UserExperience/Reference/ScreenSaver/Classes/ScreenSaverView_Class/ScreenSaverView_Class.pdf "ScreenSaverView Class Reference"
[4]: https://github.com/AerialScreensaver/ScreenSaverMinimal "GitHub - AerialScreensaver/ScreenSaverMinimal: Template for Screensaver for macOS using Swift 5, compatible with macOS 15.6 (older branch available)"
[5]: https://www.gabrieluribe.me/blog/how-to-distribute-a-screensaver-on-macos-2022 "How to distribute a screensaver on macOS in 2024 ⚙️"

