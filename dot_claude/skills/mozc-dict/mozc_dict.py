# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "protobuf>=6.0",
# ]
# ///

# mozc_dict.py - Mozc ユーザー辞書 CLI 管理ツール
# proto定義取得元: fcitx/mozc コミット acc6b842
# https://github.com/fcitx/mozc/blob/acc6b842/src/protocol/user_dictionary_storage.proto

import sys
import os
import fcntl
import random
import argparse
import tempfile
from datetime import datetime
from pathlib import Path

# pb2.py はこのスクリプトと同じディレクトリにある
sys.path.insert(0, str(Path(__file__).parent))
import user_dictionary_storage_pb2 as pb2

DB_PATH = Path.home() / ".config/mozc/user_dictionary.db"

# 日本語品詞名 → PosType enum 名のマッピング
POS_MAP = {
    "名詞":           "NOUN",
    "短縮よみ":        "ABBREVIATION",
    "サジェストのみ":   "SUGGESTION_ONLY",
    "固有名詞":        "PROPER_NOUN",
    "人名":           "PERSONAL_NAME",
    "姓":             "FAMILY_NAME",
    "名":             "FIRST_NAME",
    "組織":           "ORGANIZATION_NAME",
    "地名":           "PLACE_NAME",
    "名詞サ変":        "SA_IRREGULAR_CONJUGATION_NOUN",
    "名詞形動":        "ADJECTIVE_VERBAL_NOUN",
    "数":             "NUMBER",
    "アルファベット":   "ALPHABET",
    "記号":           "SYMBOL",
    "顔文字":         "EMOTICON",
    "副詞":           "ADVERB",
    "連体詞":         "PRENOUN_ADJECTIVAL",
    "接続詞":         "CONJUNCTION",
    "感動詞":         "INTERJECTION",
    "接頭語":         "PREFIX",
    "助数詞":         "COUNTER_SUFFIX",
    "接尾一般":        "GENERIC_SUFFIX",
    "接尾人名":        "PERSON_NAME_SUFFIX",
    "接尾地名":        "PLACE_NAME_SUFFIX",
    "動詞ワ行五段":     "WA_GROUP1_VERB",
    "動詞カ行五段":     "KA_GROUP1_VERB",
    "動詞サ行五段":     "SA_GROUP1_VERB",
    "動詞タ行五段":     "TA_GROUP1_VERB",
    "動詞ナ行五段":     "NA_GROUP1_VERB",
    "動詞マ行五段":     "MA_GROUP1_VERB",
    "動詞ラ行五段":     "RA_GROUP1_VERB",
    "動詞ガ行五段":     "GA_GROUP1_VERB",
    "動詞バ行五段":     "BA_GROUP1_VERB",
    "動詞ハ行四段":     "HA_GROUP1_VERB",
    "動詞一段":        "GROUP2_VERB",
    "動詞カ変":        "KURU_GROUP3_VERB",
    "動詞サ変":        "SURU_GROUP3_VERB",
    "動詞ザ変":        "ZURU_GROUP3_VERB",
    "動詞ラ変":        "RU_GROUP3_VERB",
    "形容詞":         "ADJECTIVE",
    "終助詞":         "SENTENCE_ENDING_PARTICLE",
    "句読点":         "PUNCTUATION",
    "独立語":         "FREE_STANDING_WORD",
    "抑制単語":        "SUPPRESSION_WORD",
}

# PosType enum 名 → 日本語品詞名（逆引き用）
POS_REVERSE = {v: k for k, v in POS_MAP.items()}


def get_pos_value(pos_name: str):
    """日本語品詞名から PosType の整数値を返す。無効な場合は None。"""
    enum_name = POS_MAP.get(pos_name)
    if enum_name is None:
        return None
    return getattr(pb2.UserDictionary.PosType, enum_name)


def load_db(db_path: Path) -> pb2.UserDictionaryStorage:
    """辞書 DB を読み込む。ファイルが存在しない場合は空の Storage を返す。"""
    storage = pb2.UserDictionaryStorage()
    if db_path.exists():
        storage.ParseFromString(db_path.read_bytes())
    return storage


def get_or_create_dict(storage: pb2.UserDictionaryStorage) -> pb2.UserDictionary:
    """最初の辞書を返す。辞書が 0 個なら「ユーザー辞書 1」を新規作成する。"""
    if len(storage.dictionaries) == 0:
        d = storage.dictionaries.add()
        d.id = random.getrandbits(64)
        d.name = "ユーザー辞書 1"
    return storage.dictionaries[0]


def save_db(storage: pb2.UserDictionaryStorage, db_path: Path) -> None:
    """辞書 DB を安全に書き込む（バックアップ → tmpファイル → 原子的置換）。"""
    # バックアップ（既存ファイルがある場合）
    if db_path.exists():
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        bak_path = db_path.parent / f"user_dictionary.db.{timestamp}.bak"
        bak_path.write_bytes(db_path.read_bytes())
        # 古いバックアップを削除（最新 5 件を保持）
        bak_files = sorted(db_path.parent.glob("user_dictionary.db.*.bak"))
        for old in bak_files[:-5]:
            old.unlink()
        orig_mode = db_path.stat().st_mode
    else:
        orig_mode = 0o600

    data = storage.SerializeToString()

    # tmpファイルに書き込んで原子的に置換
    db_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=db_path.parent)
    try:
        os.chmod(tmp_path, orig_mode)
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, db_path)
    except Exception:
        os.unlink(tmp_path)
        raise


def reload_mozc() -> None:
    """mozc_server を終了して辞書を反映させる（失敗しても続行）。"""
    import subprocess
    try:
        subprocess.run(["killall", "mozc_server"], capture_output=True)
        print("mozc_server を再起動しました。")
    except Exception as e:
        print(f"mozc_server の再起動に失敗しました（無視）: {e}", file=sys.stderr)


def open_lock(db_path: Path):
    """排他ロック用のファイルオブジェクトを返す（with 文で使う）。"""
    lock_path = db_path.parent / "user_dictionary.db.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    return open(lock_path, "ab")


# ─── サブコマンド実装 ─────────────────────────────────────────────────────────

def cmd_add(args, db_path: Path) -> None:
    yomi, word, pos_name = args.yomi, args.word, args.pos

    if not yomi:
        print("エラー: 読みが空です。", file=sys.stderr)
        sys.exit(1)
    if not word:
        print("エラー: 単語が空です。", file=sys.stderr)
        sys.exit(1)

    pos_val = get_pos_value(pos_name)
    if pos_val is None:
        print(f"エラー: 無効な品詞「{pos_name}」", file=sys.stderr)
        print(f"使用可能な品詞: {', '.join(POS_MAP.keys())}", file=sys.stderr)
        sys.exit(1)

    with open_lock(db_path) as lock_f:
        fcntl.flock(lock_f, fcntl.LOCK_EX)
        storage = load_db(db_path)
        d = get_or_create_dict(storage)

        # 重複チェック
        for entry in d.entries:
            if entry.key == yomi and entry.value == word and entry.pos == pos_val:
                print(f"警告: 「{yomi}」→「{word}」（{pos_name}）は既に登録されています。")
                return

        if args.dry_run:
            print(f"[dry-run] 追加: {yomi}\t{word}\t{pos_name}")
            return

        e = d.entries.add()
        e.key = yomi
        e.value = word
        e.pos = pos_val
        save_db(storage, db_path)

    print(f"追加しました: {yomi} → {word}（{pos_name}）")
    if args.reload:
        reload_mozc()


def cmd_list(args, db_path: Path) -> None:
    storage = load_db(db_path)
    if not storage.dictionaries:
        print("（辞書が空です）")
        return

    for d in storage.dictionaries:
        print(f"【{d.name}】 ({len(d.entries)} 件)")
        for e in d.entries:
            pos_enum_name = pb2.UserDictionary.PosType.Name(e.pos)
            pos_jp = POS_REVERSE.get(pos_enum_name, pos_enum_name)
            print(f"  {e.key}\t{e.value}\t{pos_jp}")


def cmd_delete(args, db_path: Path) -> None:
    yomi, word = args.yomi, args.word

    with open_lock(db_path) as lock_f:
        fcntl.flock(lock_f, fcntl.LOCK_EX)
        storage = load_db(db_path)

        deleted = 0
        for d in storage.dictionaries:
            before = len(d.entries)
            keep = [e for e in d.entries if not (e.key == yomi and e.value == word)]
            deleted += before - len(keep)
            del d.entries[:]
            d.entries.extend(keep)

        if deleted == 0:
            print(f"「{yomi}」→「{word}」は見つかりませんでした。")
            return

        if args.dry_run:
            print(f"[dry-run] 削除: {yomi}\t{word} ({deleted} 件)")
            return

        save_db(storage, db_path)

    print(f"削除しました: {yomi} → {word}（{deleted} 件）")
    if args.reload:
        reload_mozc()


def cmd_import_tsv(args, db_path: Path) -> None:
    tsv_path = Path(args.file)
    if not tsv_path.exists():
        print(f"エラー: ファイルが見つかりません: {tsv_path}", file=sys.stderr)
        sys.exit(1)

    with open_lock(db_path) as lock_f:
        fcntl.flock(lock_f, fcntl.LOCK_EX)
        storage = load_db(db_path)
        d = get_or_create_dict(storage)
        existing = {(e.key, e.value, e.pos) for e in d.entries}

        added = skipped = 0
        for lineno, line in enumerate(tsv_path.read_text(encoding="utf-8").splitlines(), 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue

            parts = line.split("\t")
            if len(parts) < 2:
                print(f"警告: {lineno} 行目をスキップ（フォーマット不正）: {line!r}", file=sys.stderr)
                skipped += 1
                continue

            yomi, word = parts[0], parts[1]
            pos_name = parts[2] if len(parts) >= 3 else "名詞"
            pos_val = get_pos_value(pos_name)
            if pos_val is None:
                print(f"警告: {lineno} 行目をスキップ（無効な品詞「{pos_name}」）", file=sys.stderr)
                skipped += 1
                continue

            if (yomi, word, pos_val) in existing:
                skipped += 1
                continue

            if args.dry_run:
                print(f"[dry-run] 追加: {yomi}\t{word}\t{pos_name}")
            else:
                e = d.entries.add()
                e.key = yomi
                e.value = word
                e.pos = pos_val
                existing.add((yomi, word, pos_val))
            added += 1

        if not args.dry_run:
            save_db(storage, db_path)

    print(f"インポート完了: {added} 件追加、{skipped} 件スキップ")
    if args.reload and not args.dry_run:
        reload_mozc()


def cmd_export_tsv(args, db_path: Path) -> None:
    storage = load_db(db_path)

    lines = []
    for d in storage.dictionaries:
        for e in d.entries:
            pos_enum_name = pb2.UserDictionary.PosType.Name(e.pos)
            pos_jp = POS_REVERSE.get(pos_enum_name, pos_enum_name)
            lines.append(f"{e.key}\t{e.value}\t{pos_jp}")

    output = "\n".join(lines)
    if args.file:
        Path(args.file).write_text(output + "\n", encoding="utf-8")
        print(f"エクスポートしました: {args.file}（{len(lines)} 件）")
    else:
        print(output)


# ─── エントリポイント ──────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Mozc ユーザー辞書 CLI 管理ツール",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--db", default=str(DB_PATH), help="辞書 DB のパス（デフォルト: ~/.config/mozc/user_dictionary.db）")

    # --reload / --dry-run はサブコマンドの後ろに書けるよう各サブパーサーに継承させる
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--reload", action="store_true", help="変更後に mozc_server を再起動して辞書を反映")
    common.add_argument("--dry-run", action="store_true", help="実際には書き込まず、変更内容を表示する")

    sub = parser.add_subparsers(dest="command", required=True)

    p_add = sub.add_parser("add", parents=[common], help="単語を追加する")
    p_add.add_argument("yomi", help="読み")
    p_add.add_argument("word", help="単語")
    p_add.add_argument("pos", nargs="?", default="名詞", help="品詞（デフォルト: 名詞）")

    sub.add_parser("list", help="登録済み単語を一覧表示する")

    p_del = sub.add_parser("delete", parents=[common], help="単語を削除する")
    p_del.add_argument("yomi", help="読み")
    p_del.add_argument("word", help="単語")

    p_imp = sub.add_parser("import-tsv", parents=[common], help="TSV ファイルから一括登録する")
    p_imp.add_argument("file", help="TSV ファイルのパス")

    p_exp = sub.add_parser("export-tsv", help="TSV ファイルへエクスポートする")
    p_exp.add_argument("file", nargs="?", help="出力ファイルのパス（省略時は stdout）")

    args = parser.parse_args()
    db_path = Path(args.db)

    if args.command == "add":
        cmd_add(args, db_path)
    elif args.command == "list":
        cmd_list(args, db_path)
    elif args.command == "delete":
        cmd_delete(args, db_path)
    elif args.command == "import-tsv":
        cmd_import_tsv(args, db_path)
    elif args.command == "export-tsv":
        cmd_export_tsv(args, db_path)


if __name__ == "__main__":
    main()
