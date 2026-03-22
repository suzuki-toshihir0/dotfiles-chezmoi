#!/usr/bin/env bash
# Copilot からの PR レビューコメントを取得して JSON で出力する
# Usage: check_copilot_comments.sh OWNER REPO PR_NUMBER
set -euo pipefail

OWNER="${1:?Usage: $0 OWNER REPO PR_NUMBER}"
REPO="${2:?Usage: $0 OWNER REPO PR_NUMBER}"
PR_NUMBER="${3:?Usage: $0 OWNER REPO PR_NUMBER}"

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# 1回目: reviewRequests, reviews, 最初のスレッドページを一括取得
RESPONSE=$(gh api graphql \
  -F owner="$OWNER" \
  -F name="$REPO" \
  -F number="$PR_NUMBER" \
  -f query='
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewRequests(first: 30) {
        nodes {
          requestedReviewer {
            ... on User { login }
            ... on Bot { login }
            ... on Team { name }
          }
        }
      }
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          path
          line
          comments(first: 1) {
            nodes {
              databaseId
              author { login }
              body
            }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
      reviews(last: 30) {
        nodes {
          author { login }
          body
          state
        }
      }
    }
  }
}')

# reviewRequests と reviews は1回目のみ取得（以降のページングでは不要）
echo "$RESPONSE" | jq '.data.repository.pullRequest.reviewRequests' > "$TMPDIR_WORK/review_requests.json"
echo "$RESPONSE" | jq '.data.repository.pullRequest.reviews' > "$TMPDIR_WORK/reviews.json"

# スレッドを一時ファイルに蓄積
echo "$RESPONSE" | jq '.data.repository.pullRequest.reviewThreads.nodes' > "$TMPDIR_WORK/threads.json"

# 2ページ目以降: reviewThreads のみ取得（GraphQL変数で cursor を渡す）
HAS_NEXT=$(echo "$RESPONSE" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage')
CURSOR=$(echo "$RESPONSE" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor')

while [ "$HAS_NEXT" = "true" ]; do
  RESPONSE=$(gh api graphql \
    -F owner="$OWNER" \
    -F name="$REPO" \
    -F number="$PR_NUMBER" \
    -F cursor="$CURSOR" \
    -f query='
query($owner: String!, $name: String!, $number: Int!, $cursor: String!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $cursor) {
        nodes {
          id
          isResolved
          path
          line
          comments(first: 1) {
            nodes {
              databaseId
              author { login }
              body
            }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}')

  # スレッドを追加
  echo "$RESPONSE" | jq '.data.repository.pullRequest.reviewThreads.nodes' >> "$TMPDIR_WORK/threads_extra.json"

  HAS_NEXT=$(echo "$RESPONSE" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage')
  CURSOR=$(echo "$RESPONSE" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor')
done

# 全スレッドを結合（--slurp で stdin 経由。引数長制限を回避）
if [ -f "$TMPDIR_WORK/threads_extra.json" ]; then
  cat "$TMPDIR_WORK/threads.json" "$TMPDIR_WORK/threads_extra.json" | jq -s 'add' > "$TMPDIR_WORK/all_threads.json"
else
  cp "$TMPDIR_WORK/threads.json" "$TMPDIR_WORK/all_threads.json"
fi

# 結果を整形（stdin で all_threads を渡し、引数長制限を回避）
jq -n --argjson pr "$PR_NUMBER" \
  --slurpfile threads "$TMPDIR_WORK/all_threads.json" \
  --slurpfile reviews "$TMPDIR_WORK/reviews.json" \
  --slurpfile requests "$TMPDIR_WORK/review_requests.json" \
'{
  pr_number: $pr,
  # reviewRequests を最優先: 再レビュー中なら過去の完了状態より PENDING が正しい
  copilot_review_status: (
    if ([$requests[0].nodes[]
         | select(.requestedReviewer.login // .requestedReviewer.name | test("opilot"; "i"))] | length > 0)
    then "PENDING"
    elif ([$reviews[0].nodes[]
           | select(.author.login | test("opilot"; "i"))] | length > 0)
    then ([$reviews[0].nodes[]
           | select(.author.login | test("opilot"; "i"))
           | .state] | last)
    else "NOT_REQUESTED"
    end
  ),
  threads: [
    $threads[0][]
    | select(.isResolved == false)
    | select(.comments.nodes[0].author.login | test("opilot"; "i"))
    | {
        thread_id: .id,
        is_resolved: .isResolved,
        path: .path,
        line: .line,
        comment_id: .comments.nodes[0].databaseId,
        author: .comments.nodes[0].author.login,
        body: .comments.nodes[0].body
      }
  ],
  review_summaries: [
    $reviews[0].nodes[]
    | select(.author.login | test("opilot"; "i"))
    | {
        author: .author.login,
        state: .state,
        body: .body
      }
  ]
}'
