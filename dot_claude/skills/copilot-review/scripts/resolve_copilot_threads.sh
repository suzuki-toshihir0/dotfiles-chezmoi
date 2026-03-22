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
  echo '{"resolved": 0, "failed": 0, "failures": [], "message": "resolve対象のスレッドはありません"}'
  exit 0
fi

RESOLVED=0
FAILED=0
FAIL_DETAILS="[]"

while IFS= read -r THREAD_ID; do
  ERROR_OUTPUT=$(gh api graphql \
    -F threadId="$THREAD_ID" \
    -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { isResolved }
  }
}' 2>&1) && {
    RESOLVED=$((RESOLVED + 1))
  } || {
    FAILED=$((FAILED + 1))
    FAIL_DETAILS=$(echo "$FAIL_DETAILS" | jq -c --arg id "$THREAD_ID" --arg err "$ERROR_OUTPUT" '. + [{thread_id: $id, error: $err}]')
  }
done <<< "$THREAD_IDS"

jq -n --argjson resolved "$RESOLVED" --argjson failed "$FAILED" --argjson failures "$FAIL_DETAILS" \
  '{resolved: $resolved, failed: $failed, failures: $failures}'
