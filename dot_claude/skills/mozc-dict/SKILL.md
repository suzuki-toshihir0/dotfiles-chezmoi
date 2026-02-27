---
description: >-
  Mozcユーザー辞書の管理。日本語入力の予測変換辞書への単語追加・削除・一覧表示。
  ユーザーが「辞書に追加して」「変換できるようにして」「予測変換に登録して」
  などと言ったときに自動で使用する。
allowed-tools: Bash, Read
---

# Mozc ユーザー辞書管理スキル

## 概要

`uv run ~/repos/helper/mozc-dict/mozc_dict.py` を使って Mozc のユーザー辞書を操作する。
変更後は即座に反映させるため、**常に `--reload` を付けて実行する**。

## コマンド一覧

### 単語を追加する

```bash
uv run ~/repos/helper/mozc-dict/mozc_dict.py add <読み> <単語> [品詞] --reload
```

例:
```bash
uv run ~/repos/helper/mozc-dict/mozc_dict.py add ていね 丁寧 名詞 --reload
uv run ~/repos/helper/mozc-dict/mozc_dict.py add かいしゃめい 株式会社〇〇 固有名詞 --reload
```

### 登録済み単語を一覧表示する

```bash
uv run ~/repos/helper/mozc-dict/mozc_dict.py list
```

### 単語を削除する

```bash
uv run ~/repos/helper/mozc-dict/mozc_dict.py delete <読み> <単語> --reload
```

### TSV から一括インポートする

```bash
uv run ~/repos/helper/mozc-dict/mozc_dict.py import-tsv <ファイル> --reload
```

TSV フォーマット: `読み\t単語\t品詞`（品詞省略時は「名詞」）

### TSV へエクスポートする

```bash
uv run ~/repos/helper/mozc-dict/mozc_dict.py export-tsv [ファイルパス]
```

ファイルパスを省略すると stdout に出力。

## 品詞の指定方法

- **ユーザーが品詞を指定しない場合は「名詞」をデフォルトとする**
- 文脈から推測できる場合は適切な品詞を選ぶ:
  - 固有名詞（人名・地名・会社名など）→ `固有名詞` または `人名` / `地名` / `組織`
  - 動詞（〜する）→ `動詞サ変`
  - 形容詞（〜い）→ `形容詞`
  - 副詞（〜に、〜と）→ `副詞`

使用可能な品詞（全45種）:
`名詞` `短縮よみ` `サジェストのみ` `固有名詞` `人名` `姓` `名` `組織` `地名`
`名詞サ変` `名詞形動` `数` `アルファベット` `記号` `顔文字` `副詞` `連体詞`
`接続詞` `感動詞` `接頭語` `助数詞` `接尾一般` `接尾人名` `接尾地名`
`動詞ワ行五段` `動詞カ行五段` `動詞サ行五段` `動詞タ行五段` `動詞ナ行五段`
`動詞マ行五段` `動詞ラ行五段` `動詞ガ行五段` `動詞バ行五段` `動詞ハ行四段`
`動詞一段` `動詞カ変` `動詞サ変` `動詞ザ変` `動詞ラ変`
`形容詞` `終助詞` `句読点` `独立語` `抑制単語`

## 実行後の報告

実行結果をユーザーに日本語で報告する。例:
- 追加成功 → 「「てすと → テスト（名詞）」を辞書に追加し、mozc_server を再起動しました。」
- 重複あり → 「「てすと → テスト」は既に登録されています。」
- 削除成功 → 「「てすと → テスト」を辞書から削除しました。」
