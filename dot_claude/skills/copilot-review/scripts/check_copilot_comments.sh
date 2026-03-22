#!/usr/bin/env bash
# Copilot からの PR レビューコメントを取得して JSON で出力する
# Usage: check_copilot_comments.sh OWNER REPO PR_NUMBER
set -euo pipefail

OWNER="${1:?Usage: $0 OWNER REPO PR_NUMBER}"
REPO="${2:?Usage: $0 OWNER REPO PR_NUMBER}"
PR_NUMBER="${3:?Usage: $0 OWNER REPO PR_NUMBER}"

# ページネーション付きでレビュースレッドを全件取得する
ALL_THREADS="[]"
CURSOR=""

while true; do
  if [ -z "$CURSOR" ]; then
    AFTER_ARG=""
  else
    AFTER_ARG=", after: \"$CURSOR\""
  fi

  RESPONSE=$(gh api graphql \
    -F owner="$OWNER" \
    -F name="$REPO" \
    -F number="$PR_NUMBER" \
    -f query="
query(\$owner: String!, \$name: String!, \$number: Int!) {
  repository(owner: \$owner, name: \$name) {
    pullRequest(number: \$number) {
      reviewRequests(first: 30) {
        nodes {
          requestedReviewer {
            ... on User { login }
            ... on Bot { login }
            ... on Team { name }
          }
        }
      }
      reviewThreads(first: 100${AFTER_ARG}) {
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
}")

  # スレッドを蓄積
  PAGE_THREADS=$(echo "$RESPONSE" | jq '.data.repository.pullRequest.reviewThreads.nodes')
  ALL_THREADS=$(echo "$ALL_THREADS" "$PAGE_THREADS" | jq -s '.[0] + .[1]')

  # 次ページがあるか確認
  HAS_NEXT=$(echo "$RESPONSE" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage')
  if [ "$HAS_NEXT" != "true" ]; then
    break
  fi
  CURSOR=$(echo "$RESPONSE" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor')
done

# 最後のレスポンスから reviews と reviewRequests を取得（ページングはスレッドのみ）
# jq で Copilot コメントをフィルタして整形
echo "$RESPONSE" | jq --argjson pr "$PR_NUMBER" --argjson threads "$ALL_THREADS" '{
  pr_number: $pr,
  # reviewRequests を最優先でチェック: 再レビュー中なら過去の完了状態より PENDING が正しい
  copilot_review_status: (
    if ([.data.repository.pullRequest.reviewRequests.nodes[]
         | select(.requestedReviewer.login // .requestedReviewer.name | test("opilot"; "i"))] | length > 0)
    then "PENDING"
    elif ([.data.repository.pullRequest.reviews.nodes[]
           | select(.author.login | test("opilot"; "i"))] | length > 0)
    then ([.data.repository.pullRequest.reviews.nodes[]
           | select(.author.login | test("opilot"; "i"))
           | .state] | last)
    else "NOT_REQUESTED"
    end
  ),
  threads: [
    $threads[]
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
    .data.repository.pullRequest.reviews.nodes[]
    | select(.author.login | test("opilot"; "i"))
    | {
        author: .author.login,
        state: .state,
        body: .body
      }
  ]
}'
