# Technology Stack

## Frontend

### Production

| Category | Technology |
|---|---|
| Language | TypeScript |
| Framework | Nuxt.js |
| Runtime | Node.js v22 系 |
| UI / Styling | Tailwind CSS |
| Component Base | shadcn-vue |
| Build / Routing | Nuxt.js |

### Tools

| Category | Technology |
|---|---|
| Package Manager | pnpm |
| Lint | ESLint |
| Formatting | Prettier |
| Import Sorting | eslint-plugin-simple-import-sort |

### Testing

| Layer | Recommended configuration | Target |
|---|---|---|
| Unit | Vitest | 純粋な関数、composable |
| Component / Nuxt runtime | Vitest + `@vue/test-utils` + `@nuxt/test-utils` + `happy-dom` | Vue コンポーネント、Nuxt の auto-import、plugin、runtime |
| E2E | Playwright + `@nuxt/test-utils` | 実ブラウザでの画面遷移、フォーム、SSR 後の動作 |

`frontend-app/` の初期セットアップでは、Nuxt.js の実装時点における最新安定版を使用する。Node.js は v22 系の最新パッチを前提とし、解決された依存関係は pnpm の lockfile で固定する。

## Backend

### Production

| Category | Technology |
|---|---|
| Language | TypeScript |
| Runtime | Node.js |
| Framework | Fastify |

### Testing

| Category | Technology |
|---|---|
| Testing | Vitest |
