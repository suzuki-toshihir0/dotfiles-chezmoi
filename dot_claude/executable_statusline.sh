#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
MAX_TOKENS=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
DIR=$(echo "$input" | jq -r '.workspace.current_dir // ""')

# ホームディレクトリを ~ に置換
DIR="${DIR/#$HOME/\~}"

# 最大トークン数を読みやすい単位に変換（例: 200000 → 200k）
if [ "$MAX_TOKENS" -ge 1000 ] 2>/dev/null; then
    MAX_TOKENS_FMT="$((MAX_TOKENS / 1000))k"
else
    MAX_TOKENS_FMT="${MAX_TOKENS}"
fi

# プログレスバー（10文字）
FILLED=$((PCT * 10 / 100))
EMPTY=$((10 - FILLED))
BAR=$(printf "%${FILLED}s" | tr ' ' '#')$(printf "%${EMPTY}s" | tr ' ' '-')

echo "[$MODEL] $DIR  $BAR ${PCT}% / ${MAX_TOKENS_FMT}"
