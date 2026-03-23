#!/usr/bin/env bash
# PR の HEAD commit に対する GitHub Actions ワークフロー実行状態を取得して JSON で出力する
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

# commit の check suites（GitHub Actions の実行単位）を取得
# REST API を使用: GraphQL の checkSuites は app のフィルタが面倒なため
RUNS=$(gh api "repos/${OWNER}/${REPO}/actions/runs?head_sha=${HEAD_SHA}&per_page=100" \
  --jq '{
    workflow_runs: [
      .workflow_runs[] | {
        name: .name,
        status: .status,
        conclusion: .conclusion,
        html_url: .html_url
      }
    ]
  }')

# 全体のサマリを生成
echo "$RUNS" | jq '{
  workflow_runs: .workflow_runs,
  summary: {
    total: (.workflow_runs | length),
    completed: ([.workflow_runs[] | select(.status == "completed")] | length),
    in_progress: ([.workflow_runs[] | select(.status != "completed")] | length),
    succeeded: ([.workflow_runs[] | select(.conclusion == "success")] | length),
    failed: ([.workflow_runs[] | select(.conclusion == "failure")] | length),
    cancelled: ([.workflow_runs[] | select(.conclusion == "cancelled")] | length)
  },
  overall_status: (
    if (.workflow_runs | length) == 0 then "NO_WORKFLOWS"
    elif ([.workflow_runs[] | select(.status != "completed")] | length) > 0 then "IN_PROGRESS"
    elif ([.workflow_runs[] | select(.conclusion == "failure")] | length) > 0 then "FAILED"
    elif ([.workflow_runs[] | select(.conclusion == "success")] | length) == (.workflow_runs | length) then "SUCCESS"
    else "MIXED"
    end
  )
}'
