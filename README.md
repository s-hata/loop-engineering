# Loop Engineering

## Overview

Loop Engineeringでは、1つのタスクを「実装して終わり」にせず、検証結果を次の修正へ戻す有界なフィードバックループとして扱う。
Codexの内側ループと、タスク状態・worktree・再試行を管理する外側ループを分離する。

```
                         OUTER LOOP
  ┌───────────────────────────────────────────────────────────────┐
  │                                                               │
  │  make task-run                                                │
  │       │                                                       │
  │       ▼                                                       │
  │  ┌───────────────┐     ┌───────────────┐                      │
  │  │ SQLite queue  │────▶│ Git worktree  │                      │
  │  │ queued task   │     │ agent/task-N  │                      │
  │  └───────────────┘     └──────┬────────┘                      │
  │                               │ attempt N                     │
  │                               ▼                               │
  │                    ┌────────────────────┐                     │
  │                    │    INNER LOOP      │                     │
  │                    │ Codex              │                     │
  │                    │ inspect → edit     │                     │
  │                    │   → test → fix     │                     │
  │                    └─────────┬──────────┘                     │
  │                              ▼                                │
  │                    ┌────────────────────┐                     │
  │                    │    Test gate       │                     │
  │                    └──────┬───────┬─────┘                     │
  │                         pass│       │fail                     │
  │                             ▼       ▼                         │
  │                    ┌──────────────────┐  ┌──────────────┐     │
  │                    │ Verifier Codex   │  │ logs/error   │     │
  │                    │ read-only review │  │ repair       │─────┘
  │                    └──────┬─────┬─────┘  └──────────────┘     │
  │                       pass│     │fail                         │
  │                           ▼     └─────────────────────────────┘
  │                    ┌──────────┐                 next attempt  │
  │                    │  commit  │                              │
  │                    │ completed│                              │
  │                    └──────────┘                              │
  │                                                              │
  └──────────────────────────────────────────────────────────────┘
                         max_attempts → failed
```

## Loops

```
  ┌─────────────────────▶───────────────────────┐
  │ 1. Task Creator Loop                        │
  │                                             │
  │ 課題を発見                                  │
  │   ↓                                         │
  │ タスク・受入条件・テストコマンドを定義      │
  │   ↓                                         │
  │ task-runを実行                              │
  │   ↓                                         │
  │ 結果を確認                                  │
  │   ├─ 完了 → 次の課題へ                      │
  │   └─ 未完了 → タスクを修正・再投入          │
  │                                             │
  │   ┌─────────────────▶───────────────────┐   │
  │   │ 2. Orchestrator Loop                │   │
  │   │                                     │   │
  │   │ キュー → worktree → attempt         │   │
  │   │          ↓                          │   │
  │   │       Codex                         │   │
  │   │          ↓                          │   │
  │   │       test gate                     │   │
  │   │       ├─ 成功 → commit              │   │
  │   │       └─ 失敗 → repair / retry      │   │
  │   │                                     │   │
  │   │   ┌─────────────▶───────────────┐   │   │
  │   │   │ 3. Codex Inner Loop         │   │   │
  │   │   │                             │   │   │
  │   │   │ inspect → edit → test       │   │   │
  │   │   │    → observe → fix          │   │   │
  │   │   └─────────────────────────────┘   │   │
  │   └─────────────────────────────────────┘   │
  └─────────────────────────────────────────────┘
```

内側ループは、Codexが同じworktreeで実装・テスト・観察・修正を繰り返すサイクルである。外側ループは、タスク定義ファイルとSQLiteに保存した実行状態・attemptを使い、テストゲートまたはVerifier Codexの失敗内容を次のrepairへ渡す。`max_attempts`に達したら`failed`で停止し、テストゲートとVerifier Codexの両方を通過した場合だけcommitして`completed`に遷移する。

### Test gateとVerifier Codex

タスク定義は`.loop/tasks/*.md`で管理する。タイトル、実装内容、受け入れ条件、任意の自動テストコマンドを1つのファイルにまとめ、Gitでレビュー・変更履歴を管理できるようにする。`test_command`は受け入れ条件のうち、コマンドで自動検証できる部分だけを表す。

Test gateは、タスク定義に指定されたテストコマンドを実行する汎用基盤である。コマンドがないタスクではTest gateを通過扱いにし、受け入れ条件全体はCodexとVerifier Codexに渡す。判定はコマンドを実行した場合の終了コードに基づく決定的なものである。

Verifier Codexは、Test gate通過後の変更差分をread-onlyでレビューし、内部品質を確認する。正しさ、未対応のエッジケース、テストの弱体化、無関係な変更、セキュリティ上の問題を確認し、`VERDICT: PASS`または`VERDICT: FAIL`を返す。

Test gateは「要求された動作が実際に動くか」を、Verifier Codexは「実装として妥当か」を確認する。Test gateだけでは、テストに含まれていない受け入れ条件や実装上の問題を見落とす可能性があるため、Verifier Codexはテスト内容が不十分でないかもレビュー対象とする。両方を通過した場合だけcommitし、どちらかが失敗した場合はrepair/retryへ戻る。

### 構成要素

- trigger: `make task-run`
- goal: `.loop/state.db`のqueuedタスク
- task definition: `.loop/tasks/*.md`
- verification: タスク定義内の任意のtest commandによるテストゲートと、受け入れ条件・変更差分を読むVerifier Codex
- stopping rule: `max_attempts`到達またはcompleted
- memory: SQLiteの実行状態、タスク定義ファイル、ログ、worktree

### プロジェクト構成

```
./
├── Makefile
├── src/
├── tests/
├── loop/
│   ├── *.sh
│   ├── *.bats
│   ├── test_helper.bash
│   └── init.sql
│
└── .loop/
    ├── tasks/
    │   └── task-*.md
    ├── state.db
    ├── state.json
    ├── logs/
    └── worktrees/
```

`Makefile`はリポジトリのルートに置き、アプリケーション全体の入口とする。`loop/`配下のシェルスクリプト用テストは、対象スクリプトと同じディレクトリにBatsファイルを配置する。

### シェルスクリプトのテストと品質確認

`loop/`配下のテスト・lint・formatterは、ルートの`Makefile`から`sh-`プレフィックス付きのターゲットで実行する。プロジェクト共通の依存チェックは`check-deps`で実行する。

```text
make sh-test          # Batsテストを実行
make sh-lint          # ShellCheckを実行
make sh-fmt           # shfmtで整形
make sh-fmt-check     # 整形差分だけを確認
make check-deps       # 実行時依存を確認
make sh-check-dev-deps # テスト・品質確認用ツールを確認
make task-reset TASK_ID=1       # 再実行前にタスク状態をリセット
make task-reset-force TASK_ID=1 # 変更を破棄して強制リセット
make task-run                   # キュー先頭のタスクを実行
make sh-check         # 依存確認、lint、format確認、テストをまとめて実行
```

実行時依存は`git`、`codex`、`sqlite3`、`jq`、`bash`とする。開発時の依存は`bats`、`shellcheck`、`shfmt`とする。依存チェックは各コマンドの存在を確認し、不足しているものを一覧表示して失敗させる。

Batsテストは実リポジトリの`.loop/`を直接変更せず、一時Gitリポジトリと一時ディレクトリを使って実行する。

`loop/loop_e2e.bats`では、Codexをスタブに差し替えたうえで、タスク取得からworktree作成、attempt記録、テストゲート、read-only Verifier Codex、完了状態までの`loop/loop.sh run`をE2Eで検証する。Verifierの結果はJSONLログと最終メッセージに保存し、PASS以外はコミットせず修正試行へ戻す。

`loop/loop.sh run`が途中で停止してworktreeやブランチが残った場合は、`task-reset`で対象タスクのworktree・ブランチ・DB状態を整理してから再実行する。未コミット変更がある場合は`task-reset`は停止するため、内容を破棄してよい場合だけ`task-reset-force`を使う。

タスク定義ファイルは次の形式で作成し、`loop/loop.sh add`でキューに登録する。

```markdown
---
title: Add health endpoint
base_branch: main
max_attempts: 5
test_command: npm test
---

GET /healthを実装する。

## Acceptance criteria

- HTTP 200を返す
- JSONを返す
```

```bash
loop/loop.sh add .loop/tasks/task-health.md
```

新規DBの`tasks`テーブルにはタスク定義のパスと実行状態だけを保存する。旧DBの本文カラムは互換性のため残るが、`definition_path`が設定されたタスクの実行時は定義ファイルを正として読み込む。
