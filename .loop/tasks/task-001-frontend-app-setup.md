---
title: "frontend-app のプロジェクトセットアップ"
base_branch: main
max_attempts: 5
test_command: cd frontend-app && pnpm install --frozen-lockfile && pnpm lint && pnpm format:check && pnpm build
---

## Task

`frontend-app/` に、[技術スタック](../../docs/architecture/5-technology-stack.md) に定義されたフロントエンド構成の初期プロジェクトをセットアップする。

初期ページを起動・ビルドできる状態にし、import 文のソート、Lint、フォーマットの実行とチェックに必要な設定および package scripts を追加する。

アプリケーション本体とテスト実行基盤を含む初期構成として、[Testing 構成](../../docs/architecture/5-technology-stack.md#testing) に従い、以下のディレクトリと設定ファイルを用意する。

```text
frontend-app/
├── app/
│   ├── assets/
│   ├── components/
│   │   └── ui/
│   ├── composables/
│   ├── layouts/
│   ├── middleware/
│   ├── pages/
│   │   └── index.vue
│   ├── plugins/
│   ├── utils/
│   └── app.vue
├── public/
├── tests/
│   ├── unit/
│   │   └── example.spec.ts
│   ├── nuxt/
│   │   └── component.nuxt.spec.ts
│   └── e2e/
│       └── home.spec.ts
├── nuxt.config.ts
├── package.json
├── pnpm-lock.yaml
├── tsconfig.json
├── vitest.config.ts
├── playwright.config.ts
├── eslint.config.mjs
└── prettier.config.mjs
```

Nuxt のアプリケーションコードは `app/` 配下に配置し、shadcn-vue の UI コンポーネントは `app/components/ui/` 配下で管理する。

ESLint の対象範囲は、次の判断材料に基づいて設定する。

- 依存関係、Nuxt が生成するファイル、ビルド成果物、テスト成果物など、リポジトリで直接保守しないファイルは除外する。対象例は `node_modules/`、`.nuxt/`、`.output/`、`coverage/`、`playwright-report/`、`test-results/` とする。
- `app/`、`components/`、`tests/` 配下のソースコード、および `nuxt.config.ts`、`vitest.config.ts`、`playwright.config.ts`、`eslint.config.mjs`、`prettier.config.mjs` などの手書き設定ファイルは、原則として除外しない。
- Lint エラーを回避することだけを理由に、ソースコードや手書き設定ファイルを除外しない。除外が必要か迷う場合は、生成元、再生成の可否、リポジトリで保守する責任の有無を確認し、理由を設定または検証メモに残す。

上記の除外は `eslint.config.mjs` の flat config に `ignores` として設定し、`pnpm lint` の実行対象と一致させる。`.gitignore` や `.prettierignore` の内容だけに依存せず、ESLint 自身の除外設定として明示する。

## Acceptance criteria

- `frontend-app/` が [技術スタック](../../docs/architecture/5-technology-stack.md) に定義されたフロントエンド構成のプロジェクトとして構成され、依存関係と lockfile が管理されている。
- 初期ページを開発サーバーで起動でき、本番ビルドが成功する。
- [技術スタック](../../docs/architecture/5-technology-stack.md) に定義された UI 構成が導入・設定され、初期ページまたはサンプルコンポーネントから利用できる。
- [技術スタック](../../docs/architecture/5-technology-stack.md) に定義された Lint とフォーマットツールが設定され、`pnpm lint`、`pnpm format`、`pnpm format:check` を実行できる。
- import 文のソートが設定され、`pnpm lint:fix` で自動修正できる。
- `eslint.config.mjs` に、依存関係・生成物・ビルド成果物・テスト成果物だけを対象とする除外設定があり、アプリケーションコード、テストコード、手書き設定ファイルは除外されていない。
- 除外対象の判断理由が、生成元・再生成の可否・保守責任の観点から説明できる。
- [Testing 構成](../../docs/architecture/5-technology-stack.md#testing) に対応する Unit、Nuxt runtime、E2E のテストディレクトリとサンプルテストが `frontend-app/tests/` 配下に用意され、`vitest.config.ts` と `playwright.config.ts` が配置されている。
- Nuxt のアプリケーションコード、UI コンポーネント、ページ、設定ファイルが、上記のプロジェクト構成に従って配置されている。
- `pnpm install --frozen-lockfile && pnpm lint && pnpm format:check && pnpm build` が成功する。

## Constraints

- 対象範囲は `frontend-app/` の初期セットアップに限定し、`backend-app/` と Loop Engineering 本体の実装は変更しない。
- 使用するソフトウェア構成とバージョン方針は、[技術スタック](../../docs/architecture/5-technology-stack.md) に従う。解決された依存関係のバージョンは lockfile に固定する。
- import 文のソートは、[技術スタック](../../docs/architecture/5-technology-stack.md) に定義された方式を使用する。
- `pnpm format` は Prettier によるファイルの書き換え、`pnpm format:check` は書式差分の検出として提供する。
- ESLint の除外設定は、Lint エラーを隠すための包括的なパターンや、アプリケーションコード・テストコード・手書き設定ファイルの除外に使用しない。
- テストケースの拡充やアプリケーション機能の実装は今回の対象外とする。テスト実行基盤の初期設定は対象に含める。
- 認証情報、トークン、環境固有の秘密情報をリポジトリへ追加しない。

## Verification notes

`test_command` は `frontend-app/` から依存関係を lockfile どおりにインストールした後、Lint、フォーマットのチェック、本番ビルドを順に実行する。`pnpm format` はファイルを書き換えるコマンドのため、自動検証には `pnpm format:check` を使用する。Lint の検証では、除外設定が生成物・依存物・成果物に限定され、`app/`、`components/`、`tests/` と手書き設定ファイルが実際にチェック対象であることを確認する。テストディレクトリと2つのテスト設定ファイルの配置、および [Testing 構成](../../docs/architecture/5-technology-stack.md#testing) との対応はレビューで確認する。開発サーバーの画面表示と、[技術スタック](../../docs/architecture/5-technology-stack.md) に定義された UI 構成の見た目も、コマンド成功後にレビューで確認する。
