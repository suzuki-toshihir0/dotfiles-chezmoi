#!/usr/bin/env bash
# レビューボットからの未 resolve レビュースレッドを resolve する
# bots.json の auto_resolve に含まれるボットのスレッドのみ対象
# Usage: resolve_bot_threads.sh OWNER REPO PR_NUMBER
set -euo pipefail

OWNER="${1:?Usage: $0 OWNER REPO PR_NUMBER}"
REPO="${2:?Usage: $0 OWNER REPO PR_NUMBER}"
PR_NUMBER="${3:?Usage: $0 OWNER REPO PR_NUMBER}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# check スクリプトで未 resolve のボットスレッドを取得
RESULT=$("$SCRIPT_DIR/check_bot_comments.sh" "$OWNER" "$REPO" "$PR_NUMBER")

# bots.json から auto_resolve 対象を読み込み
BOTS_JSON=$(cat "$SCRIPT_DIR/bots.json")

# auto_resolve 対象のスレッド ID を抽出
THREAD_IDS=$(echo "$RESULT" | jq -r --argjson bots "$BOTS_JSON" \
  '[.threads[] | select(.bot as $b | $bots.auto_resolve | index($b) != null)] | .[].thread_id')

# auto_resolve 対象外のスレッドを報告用に抽出
SKIPPED=$(echo "$RESULT" | jq --argjson bots "$BOTS_JSON" \
  '[.threads[] | select(.bot as $b | $bots.auto_resolve | index($b) == null)
   | {thread_id: .thread_id, bot: .bot}]')

RESOLVED=0
FAILED=0
FAIL_DETAILS="[]"

if [ -z "$THREAD_IDS" ]; then
  jq -n --argjson skipped "$SKIPPED" \
    '{resolved: 0, failed: 0, failures: [], skipped: $skipped}'
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

jq -n --argjson resolved "$RESOLVED" \
  --argjson failed "$FAILED" \
  --argjson failures "$FAIL_DETAILS" \
  --argjson skipped "$SKIPPED" \
  '{resolved: $resolved, failed: $failed, failures: $failures, skipped: $skipped}'
