#!/bin/bash
# ディスプレイのホットプラグを監視し、壁紙を自動設定するスクリプト

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SET_WALLPAPER="$SCRIPT_DIR/set-wallpaper.sh"

# 起動時に壁紙を設定
"$SET_WALLPAPER"

# RandRイベントを監視し、デバウンス付きで壁紙を再設定
last_trigger=0
xev -root -event randr | while read -r line; do
    now=$(date +%s)
    if [ $((now - last_trigger)) -ge 2 ]; then
        last_trigger=$now
        sleep 2
        "$SET_WALLPAPER"
    fi
done
