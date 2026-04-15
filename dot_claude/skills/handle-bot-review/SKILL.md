---
name: handle-bot-review
description: >-
  PR のレビューボット（Copilot, reviewdog, Devin AI 等）からのコメント確認・resolve を行う。
  レビューコメントの確認、スレッドの resolve、`/loop` での監視に使用する。
allowed-tools: Bash
---

# handle-bot-review

レビューボットからの PR レビューコメントを確認・resolve するスキル。
`author.__typename == "Bot"` で自動検出するため、新しいボットが追加されても設定変更不要。

## 使い方

- `/handle-bot-review` — 現在ブランチの PR のボットコメントを確認
- `/handle-bot-review check [PR番号]` — 指定 PR のボットコメントを確認
- `/handle-bot-review check owner/repo#PR番号` — 別リポジトリの PR を確認
- `/handle-bot-review resolve [PR番号]` — ボットスレッドを resolve

## ボット検出の仕組み

GitHub GraphQL API の `author.__typename` で `"Bot"` を自動検出する。
例外は `bots.json` で管理:

- **`ambiguous_logins`**: `github-actions` のように複数ツールが共有するアカウント。`body_pattern` でフィルタリングする
- **`auto_resolve`**: 無確認 resolve を許可するボット（Copilot, reviewdog）
- **`ignore_logins`**: 検出対象から除外するボット（informational bot 用）

## 実行手順

### Step 1: 引数を解析する

`$ARGUMENTS` を解析する:
- 第1引数が `check` or `resolve` → サブコマンドとして使用。第2引数があれば PR 指定
- 第1引数が数字 or `owner/repo#数字` → PR 指定として使用。サブコマンドは `check`
- 引数なし → サブコマンドは `check`、PR は自動特定

PR 指定の形式:
- `39` — PR番号のみ。リポジトリは現在ディレクトリから取得
- `owner/repo#39` — リポジトリ付きで指定（別リポジトリのPR確認用）

### Step 2: リポジトリ情報と PR 番号を取得する

```bash
# PR指定が owner/repo#番号 形式の場合
if [[ "$PR_ARG" == *"/"*"#"* ]]; then
  OWNER=$(echo "$PR_ARG" | cut -d'/' -f1)
  REPO=$(echo "$PR_ARG" | cut -d'/' -f2 | cut -d'#' -f1)
  PR_NUMBER=$(echo "$PR_ARG" | cut -d'#' -f2)
# PR指定が数字のみの場合
elif [[ "$PR_ARG" =~ ^[0-9]+$ ]]; then
  OWNER_REPO=$(gh repo view --json owner,name -q '.owner.login + " " + .name')
  OWNER=$(echo "$OWNER_REPO" | cut -d' ' -f1)
  REPO=$(echo "$OWNER_REPO" | cut -d' ' -f2)
  PR_NUMBER="$PR_ARG"
# PR指定なしの場合
else
  OWNER_REPO=$(gh repo view --json owner,name -q '.owner.login + " " + .name')
  OWNER=$(echo "$OWNER_REPO" | cut -d' ' -f1)
  REPO=$(echo "$OWNER_REPO" | cut -d' ' -f2)
  PR_NUMBER=$(gh pr view --json number -q '.number')
fi
```

### Step 3: サブコマンドを実行する

スクリプトのパスは `~/.claude/skills/handle-bot-review/scripts/` 配下にある。

#### check の場合

```bash
bash ~/.claude/skills/handle-bot-review/scripts/check_bot_comments.sh "$OWNER" "$REPO" "$PR_NUMBER"
```

出力はJSON。以下のフィールドを確認する:

**`review_statuses`**（ボットごとのレビュー状態マップ）:

review-request システムを使うボット（Copilot 等）のみ含まれる。
各エントリのキーはボットの login、値はレビュー状態:
- `"PENDING"` — レビュー中。「ボットのレビューが進行中です。」と報告
- `"COMMENTED"` — レビュー完了（コメントあり）
- `"APPROVED"` — 承認
- `"CHANGES_REQUESTED"` — 変更要求
- `"DISMISSED"` — 却下

review_statuses に含まれないボット（reviewdog, Devin 等）は review-request を使わないため、
PENDING 判定の対象外。

**`threads`**（未 resolve のボットスレッド）:

各スレッドに `bot` フィールドがあり、どのボットのコメントか識別できる。
- ボットごとにグループ化して報告する
- 各コメントのファイルパス・行番号・本文を表示

**`review_summaries`**（ボットのレビューサマリ）:
- あれば → ボット名とともにサマリを表示

**マージ可能性の判断:**

ボットレビューの条件を満たしたら、**ワークフローの状態も確認する**:

```bash
bash ~/.claude/skills/handle-bot-review/scripts/check_workflow_status.sh "$OWNER" "$REPO" "$PR_NUMBER"
```

出力は JSON。ワークフロー単位で最新の run のみが集計される（rerun による過去の失敗は除外済み）。
`overall_status` で判断する:
- `"SUCCESS"` — 全ワークフロー成功
- `"IN_PROGRESS"` — まだ実行中のワークフローがある
- `"FAILED"` — 失敗したワークフローがある。`workflow_runs` から失敗したものを報告する
- `"NO_RUNS"` — この HEAD SHA に紐づく workflow run が 0 件（チェック不要）
- `"MIXED"` — 成功・キャンセル等が混在。一覧で報告する

以下の**すべて**を満たす場合のみ「マージ可能」と報告する:
1. `review_statuses` に `"PENDING"` の値がない（レビューが完了している）
2. `threads` が空（全ボットの未 resolve コメントがない）
3. `overall_status` が `"SUCCESS"` または `"NO_RUNS"`（ワークフローが完了している）

つまり:
- review_statuses が全て完了 + threads 空 + ワークフロー成功 → マージ可能
- review_statuses に `PENDING` あり → レビュー進行中、待機
- threads あり → 対応が必要
- レビュー完了 + ワークフロー実行中 → 「ボットレビューは完了。ワークフローの完了を待っています。」
- レビュー完了 + ワークフロー失敗 → 「ワークフローが失敗しています。」＋失敗ワークフローの名前と URL を報告

**`/loop` での監視時:**

監視は以下の2段階で行う:

1. **ボットレビュー監視フェーズ**: ボットのレビュー完了を待つ
2. **ワークフロー監視フェーズ**: レビュー完了後、ワークフローがまだ実行中なら完了を待つ

ボットレビューが完了し、未 resolve コメントもない状態になったら、ボットの監視は終了する。
その時点でワークフローを確認し:
- ワークフローも完了（成功） → マージ可能と報告して `/loop` を停止
- ワークフローが実行中 → 「ボットレビュー完了。ワークフローの完了を待っています。」と報告し、以降はワークフロー状態のみを監視する
- ワークフローが失敗 → 失敗を報告して `/loop` を停止（ユーザーの判断が必要なため）
- ワークフローが `MIXED` → 成功/失敗/キャンセルの一覧を報告して `/loop` を停止

#### resolve の場合

1. まず `check` を実行して未 resolve スレッドを表示する
2. 未 resolve スレッドがなければ「resolve 対象のスレッドはありません。」と報告して終了
3. `auto_resolve` 対象のボット（bots.json で定義。現在: Copilot, reviewdog）のスレッドに対して:
   - 修正が必要なものはコードを修正する
   - 対応不要と判断したものは、**コードコメントで設計判断を残す**（次回pushで同じ指摘が再発するのを防ぐため）
4. `auto_resolve` **対象外**のボット（Devin 等）のスレッドがある場合:
   - 「以下のスレッドは auto_resolve 対象外です。対応方針を確認してください。」と報告する
   - resolve は実行しない
5. リプライは不要。修正はコードで示し、対応不要の判断はコードコメントで示す
6. resolve を実行する（auto_resolve 対象のみ。ユーザーへの確認は不要）:
```bash
bash ~/.claude/skills/handle-bot-review/scripts/resolve_bot_threads.sh "$OWNER" "$REPO" "$PR_NUMBER"
```
7. 出力の `skipped` フィールドに auto_resolve 対象外のスレッド情報がある場合は報告する

## API に関する重要な注意

以下の知識はスクリプトに実装済みだが、手動で API を叩く場合にも守ること:

1. **コメント取得には GraphQL を使う**。REST API `pulls/{number}/comments` はインラインコメントのみで、レビュー本文は取得できない
2. **スレッドの resolve には GraphQL mutation が必須**。REST API では resolve できない。`resolveReviewThread(input: {threadId: "..."})` を使う
3. **ボットの識別**: `author.__typename == "Bot"` で判定する。`github-actions` のような共有アカウントは `bots.json` の `body_pattern` で追加フィルタリングする
