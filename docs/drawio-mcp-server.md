# drawio-mcp-server セットアップ

## 概要

drawio-mcp-server を systemd user service で常駐させ、
Claude Code から HTTP transport で接続する構成。

stdio 方式では Claude Code セッションごとにプロセスが起動され、
WebSocket ポート 3333 の競合で "MCP failed" エラーが出るため、
HTTP transport + 共有サーバーで解決している。

## 構成

- インストール先: `~/.local/share/drawio-mcp-server/`
- systemd service: `~/.config/systemd/user/drawio-mcp-server.service`
- Claude Code 設定: `~/.claude.json` の mcpServers.drawio を `type: "http"` に設定
- エディタ: http://localhost:24017/
- MCP エンドポイント: http://localhost:24017/mcp

## 初回セットアップ

### 1. インストール

```bash
mkdir -p ~/.local/share/drawio-mcp-server
cd ~/.local/share/drawio-mcp-server
npm init -y
npm install drawio-mcp-server@1.8.0
```

### 2. アセットキャッシュ（初回のみ）

```bash
~/.volta/bin/node \
  ~/.local/share/drawio-mcp-server/node_modules/drawio-mcp-server/build/index.js \
  --editor --http-port 24017 --transport http
```

ブラウザで http://localhost:24017/ を確認後、Ctrl+C で停止。

### 3. chezmoi apply + サービス有効化

```bash
chezmoi apply \
  ~/.config/systemd/user/drawio-mcp-server.service \
  ~/.local/share/drawio-mcp-server/patch-preconfig.sh
systemctl --user daemon-reload
systemctl --user enable --now drawio-mcp-server.service
```

## 運用

### ログ確認

```bash
journalctl --user -u drawio-mcp-server.service -f
```

### 更新

```bash
cd ~/.local/share/drawio-mcp-server
npm install drawio-mcp-server@<新バージョン>
systemctl --user restart drawio-mcp-server.service
curl -s http://localhost:24017/health
```

### トラブルシュート

```bash
systemctl --user status drawio-mcp-server.service
journalctl --user -u drawio-mcp-server.service --no-pager -n 50
```

## 既知の制約

- HTTP サーバーは全インターフェース（0.0.0.0）にバインドされる
  （drawio-mcp-server に --host オプションがないため）
- ローカルPC用途なので実害は小さいが、必要ならファイアウォールで制限する
