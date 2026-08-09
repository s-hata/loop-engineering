# Loop Engineering

## Overview

```
             ┌──────────────────┐
             │     SPEC.md      │
             │ Goal / AC / 制約 │
             └────────┬─────────┘
                      │
                      ▼
              ┌───────────────┐
        ┌────▶│  Codex exec   │
        │     │ Implement/Fix │
        │     └───────┬───────┘
        │             │
        │             ▼
        │      ┌─────────────┐
        │      │   verify    │
        │      │ test/lint   │
        │      │ typecheck   │
        │      └──────┬──────┘
        │             │
        │       fail  │  pass
        │             │
        │             ├──────────────▶ DONE
        │             │
        │             ▼
        │      feedback.log
        │             │
        └─────────────┘

             max iterations
                  │
                  ▼
                 STOP
```

## Loops

```
Inner loop

Codex
 ├─ inspect
 ├─ edit
 ├─ test
 ├─ observe
 └─ fix


Outer loop

Codex
 ↓
verification
 ↓
Codex
 ↓
verification
```

### 構成要素

- trigger
- goal
- verification
- stopping rule
- memory

### プロジェクト構成

```
./
├── AGENTS.md
├── src/
├── tests/
├── scripts/
│   └── verify.sh
│
└── .loop/
    ├── SPEC.md
    ├── PROMPT.md
    ├── STATE.md
    ├── feedback.txt
    ├── run.sh
    └── runs/
```
