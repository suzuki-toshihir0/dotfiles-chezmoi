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
- プロダクトコード（継続的にメンテナンスされるコード）を新規実装する際は、t_wadaの推奨するTDD（Red→Green→Refactor）で進める
- 使い捨てスクリプト・設定ファイル編集・dotfiles管理・相談対応など、プロダクトコード以外の作業はこの限りではない

## 調査の姿勢

- **「わからない」は調査不足のサインとして扱う。** 調べれば分かることは必ず調べてから判断を示す
- 事象が解消したように見えても原因が明確でない場合は調査を継続する。「動いた」と「原因が分かった」は別物

## PC環境のルール

### dotfiles（chezmoi）
- dotfiles は chezmoi で管理されている（`/home/suzuki/.local/share/chezmoi/`）
- `~/.zshrc` や `~/.claude/CLAUDE.md` などを直接編集してはいけない。必ずソースファイルを編集して `chezmoi apply` で反映する
- chezmoi リポジトリへの変更は **必ずPR経由**で main にマージする（直接 push 禁止）
