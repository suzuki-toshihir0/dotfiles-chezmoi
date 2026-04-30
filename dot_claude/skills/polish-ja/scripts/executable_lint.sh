#!/usr/bin/env bash
# 対象ファイルに textlint --fix を当てたあと、残存警告を JSON で標準出力に出す
#
# 使い方:
#   lint.sh <target-file>
#
# private prh 辞書:
#   ~/.config/polish-ja/prh.local.yml が存在すれば、自動で読み込み対象に追加する
#   （jq が必要。jq が無い場合は警告を出して local 辞書を無視する）
#
# 環境変数:
#   POLISH_JA_LOCAL_PRH: private prh 辞書のパスを上書き指定
#
# 終了コード:
#   0 が常に返る (textlint が警告を出しても 0 で終わる)。標準出力の JSON を見て判断する
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: lint.sh <target-file>" >&2
  exit 2
fi

TARGET="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEXTLINT_DIR="$SCRIPT_DIR/../textlint"
DEFAULT_CONFIG="$TEXTLINT_DIR/.textlintrc.json"
LOCAL_PRH="${POLISH_JA_LOCAL_PRH:-$HOME/.config/polish-ja/prh.local.yml}"

if [[ ! -f "$TARGET" ]]; then
  echo "target not found: $TARGET" >&2
  exit 2
fi

if [[ ! -d "$TEXTLINT_DIR/node_modules" ]]; then
  echo "textlint not installed; run scripts/setup.sh first" >&2
  exit 2
fi

CONFIG="$DEFAULT_CONFIG"
if [[ -f "$LOCAL_PRH" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "warning: $LOCAL_PRH exists but jq is not installed; ignoring local prh" >&2
  else
    TMP_CONFIG=$(mktemp --suffix=.json)
    trap "rm -f $TMP_CONFIG" EXIT
    jq --arg p "$LOCAL_PRH" '.rules.prh.rulePaths += [$p]' "$DEFAULT_CONFIG" > "$TMP_CONFIG"
    CONFIG="$TMP_CONFIG"
  fi
fi

cd "$TEXTLINT_DIR"
./node_modules/.bin/textlint --config "$CONFIG" --fix "$TARGET" >/dev/null 2>&1 || true
./node_modules/.bin/textlint --config "$CONFIG" --format json "$TARGET" 2>/dev/null || true
