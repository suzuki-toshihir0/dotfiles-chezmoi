#!/usr/bin/env bash
# polish-ja skill 用の textlint 環境を初回セットアップする
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEXTLINT_DIR="$SCRIPT_DIR/../textlint"

if [[ -d "$TEXTLINT_DIR/node_modules" ]]; then
  exit 0
fi

cd "$TEXTLINT_DIR"
npm install --silent
