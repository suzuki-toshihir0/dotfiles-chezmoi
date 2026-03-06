#!/bin/bash
# =============================================================================
# drawio-mcp-server PreConfig.js パッチスクリプト
# =============================================================================
#
# 概要:
#   drawio-mcp-server が ~/.cache/drawio-mcp-server/webapp/ に展開する
#   draw.io のアセットに対して、エディタのデフォルト設定を上書きする。
#
# なぜ必要か:
#   drawio-mcp-server は draw.io の Web アプリを丸ごとダウンロードして
#   ローカルで配信している。エディタの設定を変えるには、アセット内の
#   PreConfig.js を直接編集するしかない。
#   ただしアセットは再ダウンロード時に上書きされるため、
#   systemd の ExecStartPost で毎回パッチを当てる。
#
# 設定内容:
#   - DRAWIO_CONFIG.defaultAdaptiveColors = "none"
#       → adaptive color を無効化（常に白ベースの配色）
#   - DRAWIO_CONFIG.pageFormat = {width: 1169, height: 827}
#       → デフォルトの用紙サイズを A4 横向きにする
#       → draw.io 内部単位: A4 = 827x1169、横向きなので width/height を入れ替え
#   - urlParams['dark'] = '0'
#       → ライトモードを強制（システムのダークモードに追従しない）
#
# 呼び出し元:
#   ~/.config/systemd/user/drawio-mcp-server.service の ExecStartPost
#
# 変更が不要になったら:
#   1. このスクリプトを削除
#   2. service ファイルから ExecStartPost 行を削除
#   3. chezmoi apply で反映
# =============================================================================

PRECONFIG="$HOME/.cache/drawio-mcp-server/webapp/js/PreConfig.js"

if [ ! -f "$PRECONFIG" ]; then
    echo "patch-preconfig.sh: PreConfig.js not found, skipping" >&2
    exit 0
fi

# 既にパッチ済みかチェック（二重適用を防止）
if grep -q 'defaultAdaptiveColors' "$PRECONFIG"; then
    exit 0
fi

# DRAWIO_CONFIG = null; の行を設定オブジェクトに置換
sed -i 's|^window\.DRAWIO_CONFIG = null;.*|window.DRAWIO_CONFIG = {\
\tdefaultAdaptiveColors: "none",\
\tpageFormat: {width: 1169, height: 827}\
};|' "$PRECONFIG"

# ライトモード強制を末尾に追加
echo "urlParams['dark'] = '0';" >> "$PRECONFIG"

echo "patch-preconfig.sh: PreConfig.js patched successfully"
