---
name: handle-copilot-review
description: >-
  GitHub CopilotからのPRレビューコメントの確認・resolveを行う。
  PRのCopilotコメント対応、レビューコメントの確認、スレッドのresolve、
  `/loop` での監視に使用する。
allowed-tools: Bash
---

# handle-copilot-review

GitHub Copilot からの PR レビューコメントを確認・resolve するスキル。

## 使い方

- `/handle-copilot-review` — 現在ブランチの PR の Copilot コメントを確認
- `/handle-copilot-review check [PR番号]` — 指定 PR の Copilot コメントを確認
- `/handle-copilot-review check owner/repo#PR番号` — 別リポジトリの PR を確認
- `/handle-copilot-review resolve [PR番号]` — Copilot スレッドを resolve

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

スクリプトのパスは `~/.claude/skills/handle-copilot-review/scripts/` 配下にある。

#### check の場合

```bash
bash ~/.claude/skills/handle-copilot-review/scripts/check_copilot_comments.sh "$OWNER" "$REPO" "$PR_NUMBER"
```

出力はJSON。**まず `copilot_review_status` を確認し、状態に応じて報告内容を変える**:

**`copilot_review_status`**（Copilot のレビュー状態）:
- `"PENDING"` — **Copilot がレビュー中。まだ完了していない。** 「Copilot のレビューが進行中です。完了を待っています。」と報告し、コメントの有無は報告しない（まだ増える可能性がある）
- `"COMMENTED"` — Copilot がレビュー完了（コメントあり）。コメント内容を報告する
- `"APPROVED"` — Copilot が承認。指摘なし
- `"CHANGES_REQUESTED"` — Copilot が変更を要求。コメント内容を報告する
- `"DISMISSED"` — Copilot のレビューが却下された。再レビューが必要か確認する
- `"NOT_REQUESTED"` — Copilot がレビュワーに設定されていない。「Copilot はこの PR のレビュワーに設定されていません。」と報告する

**`threads`**（未 resolve のインラインコメント、`PENDING` 以外の場合に報告）:
- 空 → 「Copilot からの未 resolve コメントはありません。」
- 要素あり → 各コメントのファイルパス・行番号・本文を表示

**`review_summaries`**（レビュー本文）:
- あれば → レビュー全体のサマリも表示

**マージ可能性の判断:**
以下の**両方**を満たす場合のみ「マージ可能」と報告する:
1. `copilot_review_status` が `PENDING` でない（レビューが完了している）
2. `threads` が空（未 resolve のコメントがない）

つまり:
- `COMMENTED` + `threads` 空 → マージ可能
- `APPROVED` → マージ可能
- `COMMENTED` + `threads` あり → 対応が必要
- `CHANGES_REQUESTED` → 変更要求あり、対応が必要
- `PENDING` → レビュー進行中、待機

#### resolve の場合

1. まず `check` を実行して未 resolve スレッドを表示する
2. 未 resolve スレッドがなければ「resolve 対象のスレッドはありません。」と報告して終了
3. 各スレッドに対して、修正が必要なものはコードを修正する。対応不要と判断したものは、**コードコメントで設計判断を残す**（次回pushで同じ指摘が再発するのを防ぐため）
4. リプライは不要。修正はコードで示し、対応不要の判断はコードコメントで示す
5. resolve を実行する（ここでユーザーへの確認は不要）:
```bash
bash ~/.claude/skills/handle-copilot-review/scripts/resolve_copilot_threads.sh "$OWNER" "$REPO" "$PR_NUMBER"
```

## API に関する重要な注意

以下の知識はスクリプトに実装済みだが、手動で API を叩く場合にも守ること:

1. **コメント取得には GraphQL を使う**。REST API `pulls/{number}/comments` はインラインコメントのみで、レビュー本文（Copilot の PR overview 等）は取得できない
2. **スレッドの resolve には GraphQL mutation が必須**。REST API では resolve できない。`resolveReviewThread(input: {threadId: "..."})` を使う
3. **Copilot の識別**: author の login 名に `opilot`（大文字小文字不問）を含むかで判定する。`Copilot`、`copilot-pull-request-reviewer` 等の変種に対応するため
