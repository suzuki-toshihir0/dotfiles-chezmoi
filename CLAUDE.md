# dotfiles-chezmoi

chezmoi で管理された dotfiles リポジトリ。

## 編集ルール

- 変更は **PR経由** で main にマージする（直接 push 禁止）
- `~` 配下のファイルを直接編集しない。必ず chezmoi ソースファイルを編集し `chezmoi apply` で反映する

## ツール固有の注意事項

### zeno.zsh

- `~/.config/zeno/config.yml` を変更した場合、`chezmoi apply` だけでは反映されない
- `ZENO_ENABLE_SOCK=1` によりシェルセッションごとにデーモン（deno server）が常駐しており、起動時の設定をキャッシュしている
- 設定変更後は、開いている各シェルで `zeno-restart-server` を実行するか、新しいシェルを開く必要がある
