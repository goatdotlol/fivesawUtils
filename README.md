# 🧭 fivesawUtils

> **A* Pathfinding Library for NeoScripts** — Baritone-inspired, humanized, anti-cheat compliant.

<div align="center">

![Lua](https://img.shields.io/badge/Lua-5.4-blue?logo=lua&logoColor=white)
![NeoScripts](https://img.shields.io/badge/NeoScripts-1.21.11-green)
![License](https://img.shields.io/badge/license-MIT-orange)
![Build](https://img.shields.io/github/actions/workflow/status/goatdotlol/fivesawUtils/lua-check.yml?label=syntax%20check)

**A complete A* pathfinding engine ported from Baritone/MightyMiner to Lua.**
Drop one file into your NeoScripts `libs/` folder and navigate anywhere.

</div>

---

## ✨ Features

| Feature | Description |
|---|---|
| 🔍 **A* Pathfinding** | Full A* with binary heap priority queue |
| 🧱 **4 Movement Types** | Traverse, Ascend, Descend, Diagonal |
| 🏃 **Humanized Execution** | Smooth walking with sprint toggling |
| 🎯 **Flexible Goals** | GoalBlock, GoalNear, GoalXZ, GoalY, GoalComposite |
| 🛡️ **Anti-Cheat Safe** | Real key presses, no teleports, no blatant movement |
| 📦 **Single File** | One `fivesawUtils.lua` — no dependencies |

## 📥 Installation

1. Download `fivesawUtils.lua`
2. Drop it in your NeoScripts `libs/` folder
3. Done.

```
NeoScripts/
└── libs/
    └── fivesawUtils.lua    ← here
```

## 🚀 Usage

```lua
local pathfinder = require("fivesawUtils")

-- Navigate to coordinates
pathfinder.goto(100, 64, 200, function(success)
    if success then
        print("Arrived!")
    else
        print("Path failed")
    end
end)

-- Navigate near a position (within 3 blocks)
pathfinder.gotoNear(100, 64, 200, 3, callback)

-- Cancel navigation
pathfinder.cancel()
```

### Goal Types

```lua
local goals = require("fivesawUtils").goals

-- Exact block
local g1 = goals.GoalBlock.new(100, 64, 200)

-- Within radius
local g2 = goals.GoalNear.new(100, 64, 200, 5)

-- Just X/Z (any Y)
local g3 = goals.GoalXZ.new(100, 200)

-- Just Y level
local g4 = goals.GoalY.new(64)

-- Multiple goals
local g5 = goals.GoalComposite.new({g1, g2})
```

## ⚙️ How It Works

```
┌──────────────┐    ┌───────────┐    ┌──────────────┐
│   A* Search  │───▶│   Path    │───▶│   Executor   │
│ (Binary Heap)│    │ (Nodes)   │    │ (Key Presses)│
└──────────────┘    └───────────┘    └──────────────┘
       │                                     │
       ▼                                     ▼
┌──────────────┐                    ┌──────────────┐
│  Movement    │                    │  Renderer    │
│  Generators  │                    │  (Debug)     │
│ ┌──────────┐ │                    └──────────────┘
│ │ Traverse │ │
│ │ Ascend   │ │
│ │ Descend  │ │
│ │ Diagonal │ │
│ └──────────┘ │
└──────────────┘
```

1. **A* Search** explores nodes using a binary heap, generating moves via 4 movement types
2. **Path** stores the sequence of block positions to traverse
3. **Executor** walks the path using real key presses (WASD + sprint + jump)
4. **Renderer** optionally draws the path in-world for debugging

## 🔧 Movement Types

| Type | Action | Cost |
|---|---|---|
| **Traverse** | Walk forward 1 block | 1.0 |
| **Ascend** | Jump up 1 block + forward | 2.0 |
| **Descend** | Drop down 1-3 blocks | 1.0-3.0 |
| **Diagonal** | Walk diagonally | √2 ≈ 1.414 |

## 🛡️ Anti-Cheat Design

- ✅ All movement via `input.setPressed*` (real key simulation)
- ✅ Sprint toggling with humanized timing
- ✅ Jump only when needed (block above or ascend)
- ✅ No teleportation, no velocity modification
- ✅ Natural-looking pathfinding (no perfect straight lines)

## 📄 License

MIT — Free to use, modify, and distribute.

---

<div align="center">

**Made by [fivesaw](https://github.com/goatdotlol)** ⛏️

</div>
