#!/usr/bin/env bash
# レビューボットからの PR レビューコメントを取得して JSON で出力する
# __typename == "Bot" で自動検出、bots.json で例外管理
# Usage: check_bot_comments.sh OWNER REPO PR_NUMBER
set -euo pipefail

OWNER="${1:?Usage: $0 OWNER REPO PR_NUMBER}"
REPO="${2:?Usage: $0 OWNER REPO PR_NUMBER}"
PR_NUMBER="${3:?Usage: $0 OWNER REPO PR_NUMBER}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMPDIR_WORK=$(mktemp -d -t bot-review.XXXXXX)
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
            __typename
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
              author { __typename login }
              body
            }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
      reviews(last: 100) {
        nodes {
          author { __typename login }
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
              author { __typename login }
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

# 結果を整形
# マッチングロジック:
#   1. __typename != "Bot" → 除外
#   2. login が ignore_logins に存在 → 除外
#   3. login が ambiguous_logins に存在 → body_pattern マッチしたもののみ含める（bot タグは設定の name）
#   4. それ以外の Bot → 自動的に含める（bot タグは login）
jq -n --argjson pr "$PR_NUMBER" \
  --slurpfile bots "$SCRIPT_DIR/bots.json" \
  --slurpfile threads "$TMPDIR_WORK/all_threads.json" \
  --slurpfile reviews "$TMPDIR_WORK/reviews.json" \
  --slurpfile requests "$TMPDIR_WORK/review_requests.json" \
'{
  pr_number: $pr,

  # review_statuses: Bot 型で ambiguous_logins に含まれないもののみ
  # reviewRequests を優先: レビュー依頼中なら過去の完了状態より PENDING が正しい
  review_statuses: (
    # PENDING な Bot login を収集
    ([$requests[0].nodes[]
      | .requestedReviewer
      | select(.__typename == "Bot")
      | (.login // empty)
      | select(. as $l | [$bots[0].ignore_logins[] | select(. == $l)] | length == 0)
      | select(. as $l | ($bots[0].ambiguous_logins[$l] // null) == null)
    ]) as $pending |

    # reviews から Bot login と最終 state を収集
    ([$reviews[0].nodes[]
      | select(.author.__typename == "Bot")
      | select((.author.login // "") as $l |
          [$bots[0].ignore_logins[] | select(. == $l)] | length == 0)
      | select((.author.login // "") as $l |
          ($bots[0].ambiguous_logins[$l] // null) == null)
      | {login: .author.login, state: .state}
    ] | group_by(.login) | map({key: .[0].login, value: .[-1].state})) as $reviewed |

    # マージ: PENDING 優先
    ([$pending[], ($reviewed | .[].key)] | unique) | map(
      . as $login |
      {
        key: $login,
        value: (
          if ([$pending[] | select(. == $login)] | length > 0)
          then "PENDING"
          else ($reviewed[] | select(.key == $login) | .value)
          end
        )
      }
    ) | from_entries
  ),

  # threads: 未 resolve のボットスレッド
  threads: [
    $threads[0][]
    | select(.isResolved == false)
    | . as $t
    | ($t.comments.nodes[0] // null) as $c
    | select($c != null)
    | select(($c.author.__typename // "") == "Bot")
    | ($c.author.login // "") as $login
    | select($login != "")
    # ignore_logins チェック
    | select([$bots[0].ignore_logins[] | select(. == $login)] | length == 0)
    # ambiguous_logins チェック
    | if (($bots[0].ambiguous_logins[$login] // null) != null and
          ($bots[0].ambiguous_logins[$login] | length > 0))
      then
        # body_pattern にマッチする設定を探す。マッチしなければスキップ
        ([$bots[0].ambiguous_logins[$login][]
          | . as $entry
          | select(($c.body // "") | test($entry.body_pattern))
        ] | .[0] // empty) as $matched
        | {
            thread_id: $t.id,
            bot: $matched.name,
            is_resolved: $t.isResolved,
            path: ($t.path // null),
            line: ($t.line // null),
            comment_id: $c.databaseId,
            author: $login,
            body: ($c.body // "")
          }
      else
        {
          thread_id: $t.id,
          bot: $login,
          is_resolved: $t.isResolved,
          path: ($t.path // null),
          line: ($t.line // null),
          comment_id: $c.databaseId,
          author: $login,
          body: ($c.body // "")
        }
      end
  ],

  # review_summaries: ボットのレビューサマリ
  review_summaries: [
    $reviews[0].nodes[]
    | . as $r
    | select(($r.author.__typename // "") == "Bot")
    | ($r.author.login // "") as $login
    | select($login != "")
    | select([$bots[0].ignore_logins[] | select(. == $login)] | length == 0)
    | if (($bots[0].ambiguous_logins[$login] // null) != null and
          ($bots[0].ambiguous_logins[$login] | length > 0))
      then
        ([$bots[0].ambiguous_logins[$login][]
          | . as $entry
          | select(($r.body // "") | test($entry.body_pattern))
        ] | .[0] // empty) as $matched
        | {
            bot: $matched.name,
            author: $login,
            state: $r.state,
            body: ($r.body // "")
          }
      else
        {
          bot: $login,
          author: $login,
          state: $r.state,
          body: ($r.body // "")
        }
      end
  ]
}'
