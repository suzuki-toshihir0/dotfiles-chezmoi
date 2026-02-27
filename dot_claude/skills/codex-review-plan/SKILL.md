---
name: codex-review-plan
description: >-
  Claude Codeが作成したplan fileをOpenAI Codex CLIにレビューさせ、
  別のAIモデルの視点からフィードバックを得る。
  plan fileのレビュー、計画のセカンドオピニオンが必要なときに使用する。
disable-model-invocation: true
allowed-tools: Bash, Read, Glob
---

# codex-review-plan スキル

## 概要

Claude Codeが作成したplan fileをOpenAI Codex CLIに送り、別のAIモデルの視点からレビューを受ける。

## 呼び出し例

- `/codex-review-plan` — 最新のplan fileをデフォルトモデル（gpt-5.3-codex）でレビュー
- `/codex-review-plan /path/to/plan.md` — 指定パスのplan fileをレビュー
- `/codex-review-plan -m gpt-5.2` — モデル指定してレビュー
- `/codex-review-plan -m gpt-5.1-codex-max /path/to/plan.md` — モデル＋パス指定

## 実行手順

### Step 1: 引数を解析する

`$ARGUMENTS` を解析すること:
- `-m <model>` があればモデル名を抽出（なければデフォルト = Codex CLI任せ）
- 残りの引数があればplan fileのパスとして使用
- 引数なし → 以下の順序でplan fileを特定する:
  1. **会話コンテキストから探す（第1優先）**: 現在の会話履歴を見て `~/.claude/plans/` 配下のパスが言及されていれば、最後に登場したものを使用する
  2. **コンテキスト照合フォールバック（第2優先）**: 見当たらない場合は `ls -t ~/.claude/plans/*.md 2>/dev/null | head -5` で直近5件を取得し、それぞれを Read ツールで読んで現在の会話内容（議題・リポジトリ・技術スタック等）と照合し、最も関連性の高いものを選ぶ。選んだ理由を「〜という内容が会話と一致したため `<パス>` を選択しました」と明示すること
  3. **それでも見つからなければ**: 「`~/.claude/plans/` にplan fileが見つかりませんでした」と表示して終了

### Step 2: plan file を確認する

Read ツールで対象のplan fileを読み、内容を把握する。

### Step 3: Codex CLI でレビューを実行する

以下のコマンドを Bash ツールで実行する（タイムアウト: 300000ms）。

`PLAN_FILE` には特定したplan fileのパス、`MODEL_OPT` には `-m <model>` または空文字をセットする。
`BASENAME` はplan fileのベース名（拡張子 `.md` を除いたもの）、`OUTPUT_FILE` は `/tmp/codex-review-${BASENAME}.md` とする。

```bash
PLAN_FILE="<特定したパス>"
MODEL_OPT=""  # -m指定があれば "-m gpt-5.2" 等
BASENAME=$(basename "$PLAN_FILE" .md)
OUTPUT_FILE="/tmp/codex-review-${BASENAME}.md"

{
  cat <<'REVIEW_PROMPT'
あなたは経験豊富なソフトウェアアーキテクトです。以下の実装計画を批判的にレビューしてください。

## レビュー観点
1. 実現可能性: 技術的に無理のある箇所はないか
2. 見落としているエッジケース: 異常系、境界値、パフォーマンス等
3. 改善提案: より良い方法、設計パターン、ライブラリ
4. 代替アプローチ: 根本的に異なる解決策
5. 依存関係とリスク: 外部依存、バージョン互換性、保守性

## 出力フォーマット（日本語で回答）
### 総合評価
### 良い点
### 懸念事項・問題点（重要度: 高/中/低を付与）
### 改善提案
### 代替アプローチ（あれば）

---
## レビュー対象の計画

REVIEW_PROMPT
  cat "$PLAN_FILE"
} | codex exec $MODEL_OPT --skip-git-repo-check --ephemeral --color never \
    -s read-only -o "$OUTPUT_FILE" -
```

### Step 4: 結果を読み取って表示する

- Read ツールで `$OUTPUT_FILE`（`/tmp/codex-review-<plan名>.md`）を読む
- 出力ファイルが空または存在しない場合は「Codex CLIからの出力が得られませんでした」と通知する
- Codex CLIのレビュー内容を表示した後、Claude自身の視点でコメントを追加する
- 使用したモデル名（指定があれば指定モデル、なければ「Codex CLIデフォルト」）を明示する

## エラーハンドリング

- **plan fileなし**: 「`~/.claude/plans/` にplan fileが見つかりませんでした」
- **Codex CLI失敗**: エラー出力を表示し、認証期限切れ・ネットワーク問題・`~/.codex/auth.json` の有効性などの原因候補を提示する
- **出力ファイル空**: 「Codex CLIからの出力が得られませんでした。`codex exec` が正常に動作しているか確認してください」と通知する
