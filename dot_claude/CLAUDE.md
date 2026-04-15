# Claude User Memory

## Language Preference
ユーザーとの対話は日本語で行う。すべての回答、説明、コメントは日本語で提供すること。

## Communication Style
- 技術的な内容でも日本語で説明
- コードコメントも日本語で記述
- エラーメッセージやログの説明も日本語で提供

## Visual & Design Rules
- 色（HEXコード・RGB・色名）を指定・選択するすべての場面で、必ず `cud-compliant-design` スキルをロードしてください。

## 実装原則
- プロダクトコード（継続的にメンテナンスされるコード）を新規実装する際は、TDD（Red→Green→Refactor）で進める
- 使い捨てスクリプト・設定ファイル編集・dotfiles管理・相談対応など、プロダクトコード以外の作業はこの限りではない

## 調査の姿勢

- **「わからない」は調査不足のサインとして扱う。** 調べれば分かることは必ず調べてから判断を示す
- 事象が解消したように見えても原因が明確でない場合は調査を継続する。「動いた」と「原因が分かった」は別物
- **手元の情報を最初に確認する。** MCPツールの接続先URL・ポート番号が必要なら `.claude.json` の設定を見る。既に使っているツールやサービスの情報は、Web検索や推測の前に、設定ファイル・プロセス情報・ログなど手元にある一次情報を確認すること

## PR Review Comment の対応ルール

- レビューボット（Copilot, reviewdog, Devin AI 等）からの PR review comment に対応した場合、修正を push した後にそのコメントを resolve する
- 対応不要と判断した場合は、理由をリプライしてから resolve する

## PC環境のルール

### SSH agent（1Password）
- SSH agent は 1Password が提供している。1Password が起動していないと git push / git commit（署名付き）が失敗する
- agent socket 関連のエラーが出たら、**「1Passwordを開いてください」とユーザーに促す**こと
- `--no-gpg-sign` や署名スキップなど、署名なしへのフォールバックは禁止

### dotfiles（chezmoi）
- dotfiles は chezmoi で管理されている（`~/.local/share/chezmoi/`）
- `~/.zshrc` や `~/.claude/CLAUDE.md` などを直接編集してはいけない。必ずソースファイルを編集して `chezmoi apply` で反映する
- chezmoi リポジトリへの変更は **必ずPR経由**で main にマージする（直接 push 禁止）
