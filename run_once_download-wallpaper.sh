#!/bin/bash
# 壁紙をダウンロードする（初回のみ実行）

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
WALLPAPER_PATH="$WALLPAPER_DIR/Clearday.jpg"

if [ -f "$WALLPAPER_PATH" ]; then
    echo "壁紙は既に存在します: $WALLPAPER_PATH"
    exit 0
fi

mkdir -p "$WALLPAPER_DIR"
echo "壁紙をダウンロード中..."
curl -fsSL -o "$WALLPAPER_PATH" \
    "https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/1023077979591cdeca76aae94e0359da1707a60e/landscapes/Clearday.jpg"
echo "壁紙をダウンロードしました: $WALLPAPER_PATH"
