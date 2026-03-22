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

RESOLVED=0
FAILED=0
FAIL_DETAILS="[]"

if [ -z "$THREAD_IDS" ]; then
  jq -n '{resolved: 0, failed: 0, failures: []}'
  exit 0
fi

while IFS= read -r THREAD_ID; do
  if gh api graphql \
    -F threadId="$THREAD_ID" \
    -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { isResolved }
  }
}' > /dev/null 2>&1; then
    RESOLVED=$((RESOLVED + 1))
  else
    FAILED=$((FAILED + 1))
    FAIL_DETAILS=$(echo "$FAIL_DETAILS" | jq -c --arg id "$THREAD_ID" '. + [{thread_id: $id}]')
  fi
done <<< "$THREAD_IDS"

jq -n --argjson resolved "$RESOLVED" --argjson failed "$FAILED" --argjson failures "$FAIL_DETAILS" \
  '{resolved: $resolved, failed: $failed, failures: $failures}'
