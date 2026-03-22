#!/usr/bin/env bash
# Copilot からの PR レビューコメントを取得して JSON で出力する
# Usage: check_copilot_comments.sh OWNER REPO PR_NUMBER
set -euo pipefail

OWNER="${1:?Usage: $0 OWNER REPO PR_NUMBER}"
REPO="${2:?Usage: $0 OWNER REPO PR_NUMBER}"
PR_NUMBER="${3:?Usage: $0 OWNER REPO PR_NUMBER}"

# GraphQL でレビュースレッド、レビュー本文、レビュワー情報を一括取得
RESPONSE=$(gh api graphql \
  -F owner="$OWNER" \
  -F name="$REPO" \
  -F number="$PR_NUMBER" \
  -f query='
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewRequests(first: 10) {
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
          comments(first: 5) {
            nodes {
              databaseId
              author { login }
              body
            }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
      reviews(first: 30) {
        nodes {
          author { login }
          body
          state
        }
      }
    }
  }
}')

# jq で Copilot コメントをフィルタして整形
echo "$RESPONSE" | jq --argjson pr "$PR_NUMBER" '{
  pr_number: $pr,
  copilot_review_status: (
    if ([.data.repository.pullRequest.reviews.nodes[]
         | select(.author.login | test("opilot"; "i"))] | length > 0)
    then ([.data.repository.pullRequest.reviews.nodes[]
           | select(.author.login | test("opilot"; "i"))
           | .state] | last)
    elif ([.data.repository.pullRequest.reviewRequests.nodes[]
           | select(.requestedReviewer.login // .requestedReviewer.name | test("opilot"; "i"))] | length > 0)
    then "PENDING"
    else "NOT_REQUESTED"
    end
  ),
  threads: [
    .data.repository.pullRequest.reviewThreads.nodes[]
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
  ],
  has_next_page: .data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage
}'
