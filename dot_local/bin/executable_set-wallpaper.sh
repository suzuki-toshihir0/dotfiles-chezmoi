#!/bin/bash
# 接続中の全モニターに壁紙を設定するスクリプト

WALLPAPER_PATH="${WALLPAPER_PATH:-$HOME/Pictures/Wallpapers/Clearday.jpg}"

if [ ! -f "$WALLPAPER_PATH" ]; then
    echo "壁紙ファイルが見つかりません: $WALLPAPER_PATH" >&2
    exit 1
fi

# xrandrから接続中のモニター名を取得
connected_monitors=$(xrandr --query | grep ' connected' | awk '{print $1}')

if [ -z "$connected_monitors" ]; then
    echo "接続中のモニターが見つかりません" >&2
    exit 1
fi

for monitor in $connected_monitors; do
    property="/backdrop/screen0/monitor${monitor}/workspace0/last-image"
    style_property="/backdrop/screen0/monitor${monitor}/workspace0/image-style"

    # 壁紙パスを設定
    xfconf-query -c xfce4-desktop -p "$property" -s "$WALLPAPER_PATH" --create -t string
    # スタイルをZoomed（5）に設定
    xfconf-query -c xfce4-desktop -p "$style_property" -s 5 --create -t int

    echo "壁紙を設定しました: $monitor -> $WALLPAPER_PATH"
done
