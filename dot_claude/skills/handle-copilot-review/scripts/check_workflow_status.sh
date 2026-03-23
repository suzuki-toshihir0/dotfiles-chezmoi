#!/usr/bin/env bash
# PR の HEAD commit に対する GitHub Actions ワークフロー実行状態を取得して JSON で出力する
# ワークフロー単位で最新の run のみを集計する（rerun による過去の失敗を除外）
# Usage: check_workflow_status.sh OWNER REPO PR_NUMBER
set -euo pipefail

OWNER="${1:?Usage: $0 OWNER REPO PR_NUMBER}"
REPO="${2:?Usage: $0 OWNER REPO PR_NUMBER}"
PR_NUMBER="${3:?Usage: $0 OWNER REPO PR_NUMBER}"

# PR の HEAD commit SHA を取得
HEAD_SHA=$(gh api graphql \
  -F owner="$OWNER" \
  -F name="$REPO" \
  -F number="$PR_NUMBER" \
  -q '.data.repository.pullRequest.headRefOid' \
  -f query='
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      headRefOid
    }
  }
}')

# commit の workflow runs を全ページ取得し、ワークフロー単位で最新 run のみに絞る
# --paginate で全件取得。workflow_id でグループ化し、run_started_at が最新のものだけ残す
RUNS=$(
  gh api --paginate "repos/${OWNER}/${REPO}/actions/runs?head_sha=${HEAD_SHA}" \
    --jq '.workflow_runs[] | {
      workflow_id: .workflow_id,
      run_started_at: .run_started_at,
      name: .name,
      status: .status,
      conclusion: .conclusion,
      html_url: .html_url
    }' \
  | jq -s '{
      workflow_runs: (
        sort_by(.run_started_at)
        | group_by(.workflow_id)
        | map(.[-1])
      )
    }'
)

# 全体のサマリを生成
# 失敗判定: success と cancelled 以外の conclusion（failure, timed_out, action_required, startup_failure 等）を失敗扱い
echo "$RUNS" | jq '{
  workflow_runs: .workflow_runs,
  summary: {
    total: (.workflow_runs | length),
    completed: ([.workflow_runs[] | select(.status == "completed")] | length),
    in_progress: ([.workflow_runs[] | select(.status != "completed")] | length),
    succeeded: ([.workflow_runs[] | select(.conclusion == "success")] | length),
    failed: ([.workflow_runs[] | select(.conclusion != "success" and .conclusion != "cancelled" and .conclusion != null)] | length),
    cancelled: ([.workflow_runs[] | select(.conclusion == "cancelled")] | length)
  },
  overall_status: (
    if (.workflow_runs | length) == 0 then "NO_RUNS"
    elif ([.workflow_runs[] | select(.status != "completed")] | length) > 0 then "IN_PROGRESS"
    elif ([.workflow_runs[] | select(.conclusion != "success" and .conclusion != "cancelled" and .conclusion != null)] | length) > 0 then "FAILED"
    elif ([.workflow_runs[] | select(.conclusion == "success")] | length) == (.workflow_runs | length) then "SUCCESS"
    else "MIXED"
    end
  )
}'
