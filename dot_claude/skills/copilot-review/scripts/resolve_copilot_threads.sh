#!/usr/bin/env bash
# Copilot からの未 resolve レビュースレッドを一括 resolve する
# Usage: resolve_copilot_threads.sh OWNER REPO PR_NUMBER
set -euo pipefail

OWNER="${1:?Usage: $0 OWNER REPO PR_NUMBER}"
REPO="${2:?Usage: $0 OWNER REPO PR_NUMBER}"
PR_NUMBER="${3:?Usage: $0 OWNER REPO PR_NUMBER}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# check スクリプトで未 resolve の Copilot スレッドを取得
RESULT=$("$SCRIPT_DIR/check_copilot_comments.sh" "$OWNER" "$REPO" "$PR_NUMBER")

# スレッド ID を抽出
THREAD_IDS=$(echo "$RESULT" | jq -r '.threads[].thread_id')

if [ -z "$THREAD_IDS" ]; then
  echo '{"resolved": 0, "failed": 0, "message": "resolve対象のスレッドはありません"}'
  exit 0
fi

RESOLVED=0
FAILED=0

while IFS= read -r THREAD_ID; do
  if gh api graphql -f query="
mutation {
  resolveReviewThread(input: {threadId: \"$THREAD_ID\"}) {
    thread { isResolved }
  }
}" > /dev/null 2>&1; then
    RESOLVED=$((RESOLVED + 1))
  else
    FAILED=$((FAILED + 1))
  fi
done <<< "$THREAD_IDS"

echo "{\"resolved\": $RESOLVED, \"failed\": $FAILED}"
