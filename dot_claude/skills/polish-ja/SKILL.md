---
name: polish-ja
description: >-
  AIが書いた日本語の技術文書を、textlintによる機械的修正と
  文脈分離されたsub agentによる文章校閲で網羅的に整える。
  AIが書いた日本語のクセ（不自然な体言止め、英単語の不適切な混入、hype語、冗長表現など）を
  徹底的に直したいときに使用する。
  `/polish-ja teach <自由文>` で校閲ルール（辞書・ポリシー）を追加・更新できる。
allowed-tools: Bash, Read, Edit, Agent
---

# polish-ja スキル

## 概要

AIが書いた日本語の技術文書を、二段構成で網羅的に校閲する：

1. **textlint** による機械的な修正（表記揺れ、スタイル違反、保守的な置換）
2. **文脈分離された sub agent** による文章としての校閲（不自然な体言止め、英単語の不適切な混入、ぎこちない言い回し、AIっぽい hype 語）

成果物は **修正済みのファイルそのもの**。差分表示・承認・要約は行わない。気になればユーザーが `git diff` を打ち、気に入らなければ `git restore` で戻す。

## 校閲ルールの構成（3層）

| 層 | 場所 | 何を表現できるか |
|---|---|---|
| 機械パターン | textlint preset | 構文・記法レベルの決定的なルール（基本固定） |
| 語彙置換 | `textlint/prh.yml` (公開) / `~/.config/polish-ja/prh.local.yml` (private) | A → B の単純置換 |
| セマンティック指針 | `policy/policy.md` (公開) / `~/.config/polish-ja/policy.local.md` (private) | 自然言語の規範 |

語彙置換とセマンティック指針は `/polish-ja teach <自由文>` で追加できる。

## モード

第一引数で判定する：

- `teach` または `learn` → **教育モード** (Step T参照)
- `list` または `rules` → **一覧モード** (Step L参照)
- それ以外（ファイルパスとみなす）→ **校閲モード** (Step 1〜6参照)

---

## 校閲モード

### Step 1: 引数の検証

`$ARGUMENTS` を解析する：
- 引数が空 → 「対象ファイルパスが必要です」と表示して終了
- ファイルが存在しない → 「ファイルが見つかりません: <パス>」と表示して終了

絶対パスに正規化する。

### Step 2: 初回セットアップ

`~/.claude/skills/polish-ja/textlint/node_modules/` の有無を確認する。
無ければ Bash ツールで以下を実行：

```bash
~/.claude/skills/polish-ja/scripts/setup.sh
```

### Step 3: textlint --fix を当てる

```bash
~/.claude/skills/polish-ja/scripts/lint.sh <対象ファイルの絶対パス>
```

このスクリプトは `--fix` で機械的に修正可能な部分を対象ファイルに直接書き戻し、残存警告を JSON で標準出力に出す。残存警告は記録に残すだけで、sub agent には渡さない（sub agent は文書を独立に評価する）。

### Step 4: sub agent を起動

`Agent` ツールで sub agent を起動する：
- subagent_type: `general-purpose`
- description: `日本語校閲（polish-ja）`
- prompt: 下記テンプレートに対象ファイルの絶対パスを埋めたもの

#### 校閲プロンプトテンプレート

```
あなたは日本語の技術文書の校閲者です。文脈ゼロで以下のファイルを Read ツールで読み、AIが書いた日本語のクセを徹底的に指摘してください。

対象ファイル: <FILE_ABS_PATH>

校閲ポリシーは以下の2ファイルに記述されています。両方を Read ツールで読み、その指示に従って校閲してください:

1. /home/suzuki/.claude/skills/polish-ja/policy/policy.md (公開ポリシー、必読)
2. /home/suzuki/.config/polish-ja/policy.local.md (private ポリシー、存在すれば併用。存在しなければスキップ)

出力フォーマット (JSON のみ。説明文は不要):

[
  {
    "current": "<前後コンテキストを含む現在のテキスト。文書中でユニークになる程度の長さ>",
    "proposed": "<修正後のテキスト>",
    "reason": "<簡潔な理由（1行）>",
    "category": "<english_in_japanese | unnatural_taigendome | redundant_expression | hype_word | awkward_phrase | other>"
  }
]

提案がない場合は空配列 [] を返してください。
コードブロック・インラインコード内のテキストは校閲対象外です（ただしその周囲の地の文は対象）。
原文の主張・事実関係は変えないでください。
```

### Step 5: 提案の取捨選択と適用

sub agent が返した JSON を解析し、以下の基準で各提案を判断する：

**棄却すべき提案:**
- policy.md の「直してはいけないもの」に該当（固有名詞、コード識別子、確立した略語、訳語が定着していない技術用語など）
- 文脈上、意図的な使い分けと判断できる
- `current` が文書中でユニークでない、または不正確（`Edit` の old_string マッチに失敗するもの）

**採用すべき提案:**
- 上記以外すべて

採用した提案は `Edit` ツールで適用：
- `old_string`: 提案の `current` フィールド
- `new_string`: 提案の `proposed` フィールド

ユーザーへの逐一確認は挟まない。

### Step 6: 完了

すべての適用が終わったら、`polish-ja: 完了` とだけ表示して終了する。

---

## 教育モード（teach）

ユーザーが `/polish-ja teach <自由文>` で校閲ルールを追加するモード。

### Step T1: 引数の解析

```
/polish-ja teach <自由文>
/polish-ja teach private <自由文>
```

- `private` キーワードがあれば private 扱い
- それ以外は public 扱い

ただし、内容から **自動判定** もする（次節「公開/private の判断」参照）。明示指定があればそれを優先。

### Step T2: 反映先の判断（prh行き / policy行き）

ユーザーの自由文を解釈し、以下のいずれかに振り分ける：

**prh（語彙置換）に行くもの:**
- 「A は B と書け」「A を B に直せ」のような単純な語の置換指示
- 例: 「『シームレス』は『円滑』に直す」「『deploy』は『デプロイ』と書く」

**policy（自然言語ポリシー）に行くもの:**
- 構造的・文脈的な指示
- 単純置換に落とし込めない指示
- 例: 「箇条書きの末尾には句点を打たない」「同じ接続詞を連続して使わない」「謙譲語は控えめに」

判断に迷う場合は policy に倒す（policy のほうが表現力が高いため）。

### Step T3: 公開/private の判断と「規範／具体例の分離」

**`private` キーワード（明示指定）がある場合:**
- ユーザーの自由文すべてを private に置く（policy なら policy.local.md、prh なら prh.local.yml）
- 規範と具体例の分離はしない

**明示指定がない場合（C + D 方式）:**

teach 内容を **「規範部分」と「具体例部分」に分離** する。

- **規範部分**: 一般化可能な指示・ルール本体（例: 「同じ接続詞を連続して使わない」）
- **具体例部分**: 規範を裏付ける実例（例: 「弊社の文書で『また、〜。また、〜』が典型」）

分離結果の振り分け：
| 分離結果 | 規範の置き場 | 具体例の置き場 |
|---|---|---|
| policy 行き | `policy.md` (public) | `policy.local.md` (private) |
| prh 行き | `prh.yml` (public) | （prh は規範のみ。具体例なし） |

prh の場合は基本的に「単純置換ルール」しかないので具体例分離は不要。

policy の場合は、規範のみを public に、具体例を private に置く。具体例が無い teach 入力なら policy.md にだけ追加。

**社内用語・組織固有の語が含まれているか自動チェック**:

ユーザーの自由文に明らかな組織名・製品名・個人名と思しき固有名詞が含まれている場合（「株式会社」「Inc.」「有限会社」サフィックス、社内コードネームらしい英数字、明らかな個人名など）、その部分は具体例として private に分離する。判定に確信が持てない語が出てきたら、そのまま public に置きつつユーザーに確認を促す（過剰に private に倒さない）。

### Step T4: 反映

#### prh の場合

対象ファイル:
- public: `~/.claude/skills/polish-ja/textlint/prh.yml`
- private: `~/.config/polish-ja/prh.local.yml`（存在しなければディレクトリごと作成して `version: 1\nrules: []` で初期化）

`rules:` セクションに以下を追記：

```yaml
  - expected: <正しい表記>
    pattern: <修正対象のパターン>
```

追加前に同じ pattern が既存にないか確認し、あれば「既に登録されています」と通知。

#### policy の場合

Step T3 の分離結果に応じて、規範と具体例をそれぞれ別ファイルに追記する。

**規範**:
- 対象: `~/.claude/skills/polish-ja/policy/policy.md`（public）
  ※ ただし `private` 明示指定があった場合は `~/.config/polish-ja/policy.local.md`（private）
- 末尾の「## 追加ルール」セクションに箇条書きで追加：
  ```markdown
  - <規範を一文で>
  ```

**具体例**（あれば）:
- 対象: `~/.config/polish-ja/policy.local.md`（private、存在しなければ下記テンプレで初期化）
- 「## 追加ルール（具体例）」セクションに、対応する規範を引用しつつ追加：
  ```markdown
  - 「<対応する規範>」の例: <具体例の説明>
  ```

`policy.local.md` の初期テンプレ（初回作成時）:

```markdown
# polish-ja 校閲ポリシー（private）

このファイルは公開されない補助ポリシーです。組織固有のルールや、規範の具体例を書きます。

## 追加ルール

## 追加ルール（具体例）
```

### Step T5: 確認

追加した内容を表示する。**規範と具体例が分離されたなら両方を見せる**：

```
polish-ja teach: 以下を追加しました
- 公開: <ファイルパス>
  - <追加した規範>
- 非公開: <ファイルパス>
  - <追加した具体例（あれば）>
```

policy で「規範と具体例の分離が起きた」ときは、ユーザーが分離結果を確認できるようにする。意図と違っていればユーザーが手動で修正できるよう、ファイルパスを明示する。

辞書（prh）に追加した場合は、簡単な動作確認（textlintが新ルールをロードできるか）を行うのが望ましい：

```bash
~/.claude/skills/polish-ja/scripts/lint.sh /tmp/<ダミーファイル>
```

---

## 一覧モード（list）

`/polish-ja list` または `/polish-ja list <種別>` で登録ルールを表示する。

### Step L1: 引数の解析

- 引数なし → 全種別を表示
- `prh` / `policy` → 該当種別のみ
- `public` / `private` → 該当範囲のみ
- 組み合わせ可（例: `list policy private`）

### Step L2: 表示

各ファイルを Read で読み、整形して表示：

```
=== prh (public) ===
~/.claude/skills/polish-ja/textlint/prh.yml
- 円滑 ← シームレス
- 活用 ← レバレッジ
- します ← させていただきます

=== prh (private) ===
~/.config/polish-ja/prh.local.yml
（ファイルなし、または空）

=== policy (public) ===
~/.claude/skills/polish-ja/policy/policy.md の追加ルール部分
- ...

=== policy (private) ===
~/.config/polish-ja/policy.local.md
（ファイルなし、または空）
```

---

## 補足

### private 領域の初期化

private 辞書・ポリシーが初めて使われるとき、自動的に作成する：

```bash
mkdir -p ~/.config/polish-ja
```

- `~/.config/polish-ja/prh.local.yml` 初期内容: `version: 1\nrules: []`
- `~/.config/polish-ja/policy.local.md` 初期内容: 空ファイルまたは見出しのみ

### ファイル構成

```
~/.claude/skills/polish-ja/
├── SKILL.md                    # この手順書（安定）
├── policy/
│   └── policy.md               # 公開ポリシー
├── textlint/
│   ├── package.json + lock
│   ├── .textlintrc.json
│   ├── prh.yml                 # 公開辞書
│   └── node_modules/
└── scripts/
    ├── setup.sh                # 初回 npm install
    └── lint.sh                 # textlint --fix + 残存警告JSON取得 + private prh併用

~/.config/polish-ja/             # private、chezmoi 管理外
├── prh.local.yml               # private 辞書
└── policy.local.md             # private ポリシー
```

### エラーハンドリング

- **textlint 未インストール**: `lint.sh` が「`scripts/setup.sh` を先に実行してください」と通知
- **対象ファイル不在**: 「ファイルが見つかりません」と通知して終了
- **sub agent からの JSON 解析失敗**: 生レスポンスを表示してユーザーに知らせる
- **`Edit` の old_string マッチ失敗**: その提案だけスキップして続行
- **jq 未インストール**: private prh があっても警告のみ出して、公開辞書だけで続行

### 注意事項

- このskillは **既に書かれた文書の校閲** を行う。新規執筆の支援ではない
- sub agent はメイン会話の文脈を持たない。それが目的
- ユーザーが意図的に使った表記揺れまで書き換える可能性がある。気に入らなければ `git restore`
- 対象は Markdown が主（textlint-plugin-markdown が標準）。コードブロック・インラインコード内は textlint 側で除外される
