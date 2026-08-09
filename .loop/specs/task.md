# Task

この Node.js アプリに `GET /health` エンドポイントを追加してください。

## Acceptance Criteria

- `GET /health` が HTTP 200 を返す
- レスポンスは JSON
- レスポンス本文は次の内容である

{
  "status": "ok"
}

- 既存の `GET /` の動作を壊さない
- `/health` の自動テストを追加する
- `npm test` が成功する
