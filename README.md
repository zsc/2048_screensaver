# 2048 自动玩屏保（Expectimax + GA）

本仓库按 `AGENTS.md` 的 SPEC 实现：

- `Core2048/`：纯 Swift 核心（`UInt64` 棋盘 + 行查表 move + expectimax + value function）
- `Trainer2048/`：CLI（评估 / GA 训练，输出 `weights.json`）
- `Screensaver2048/`：macOS 屏保 `.saver`（渲染 + Timer + 多实例租约）

## 1) 先跑 CLI（强烈建议）

- 规则正确性 + 冒烟测试：
  - `cd Core2048 && swift run -c release core2048-tests`
  - 快速版：`cd Core2048 && swift run -c release core2048-tests --quick`
- 评估 baseline（不带 `--weights` 使用内置权重）：
  - `cd Trainer2048 && swift run -c release trainer eval --games 200 --seed 123 --depth 3 --sample 6`
- 训练权重（GA）：
  - `cd Trainer2048 && swift run -c release trainer init-config > config.json`
  - `cd Trainer2048 && swift run -c release trainer train --config config.json --out weights.json`
  - `cd Trainer2048 && swift run -c release trainer eval --weights weights.json --games 200 --seed 123`
- 生成单局回放（HTML）：
  - `cd Trainer2048 && swift run -c release trainer replay --seed 123 --out ../replay.html`

## 2) 构建屏保（生成 `.saver`）

屏保 bundle 会输出到 `Build/Screensaver2048.saver`。

- 构建：
  - `bash scripts/build_saver.sh`
- 安装到当前用户：
  - `bash scripts/install_saver.sh`

## 3) 安装/启用（手动步骤）

1. 打开 **系统设置** → **屏幕保护程序**（Screen Saver）
2. 在列表里选择 **Screensaver2048**
3. 点“预览”确认在跑（会自动下棋）

如果系统提示“不受信任/无法打开”，可尝试：

- 移除隔离属性（下载来的文件常见）：  
  `xattr -dr com.apple.quarantine "$HOME/Library/Screen Savers/Screensaver2048.saver"`
- 重新在系统设置里选择一次屏保，或重启系统设置

## 4) 用训练出来的权重

把训练得到的 `weights.json` 覆盖到 `Screensaver2048/Resources/weights.json`，然后重新构建 + 安装：

- `cp /path/to/weights.json Screensaver2048/Resources/weights.json`
- `bash scripts/build_saver.sh`
- `bash scripts/install_saver.sh`

## 5) 卸载

- 删除：`$HOME/Library/Screen Savers/Screensaver2048.saver`
