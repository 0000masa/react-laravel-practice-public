# EXPLAIN の読み方（検証クエリの実行計画）

対象 DB: Amazon RDS for **MariaDB 11.4**（InnoDB）。
`GET /api/posts?...&explain=1` が返す `explain` 配列＝ `EXPLAIN <SELECT>` の結果。各列と各値が何を表すかをまとめる。

前提の理屈（index をどこに張るか、効かないケース）は [indexing.md](./indexing.md)、実験全体は [query-performance-experiment.md](./query-performance-experiment.md)。

---

## 1. EXPLAIN とは

`EXPLAIN` はクエリを**実行せずに**、オプティマイザが立てた実行計画（どのテーブルをどの順で、どの index を使い、何行読むつもりか）を返す。所要時間ではなく「**なぜその時間になるのか**」を示す。

```sql
EXPLAIN SELECT * FROM posts WHERE title LIKE '%NEEDLE%' ORDER BY id DESC LIMIT 50;
```

学習UI（`/posts`）では `explain=1` を付けると、この結果が `table / type / possible_keys / key / rows / Extra` の表で出る。

---

## 2. 各列の意味

MariaDB の標準 EXPLAIN が返す列。UIで表示しているのは太字の6つ。

| 列 | 意味 | 読みどころ |
| --- | --- | --- |
| `id` | SELECT の識別子。単純なクエリは常に `1`。サブクエリ/UNION があると増える | 今回の検証は単一SELECTなので常に1 |
| `select_type` | SELECT の種類（`SIMPLE` / `SUBQUERY` / `DERIVED` / `UNION` …） | 検証クエリは `SIMPLE` |
| **`table`** | この行が対象とするテーブル（別名） | `posts` |
| **`type`** | **アクセス方法（結合/走査の型）。最重要**。§3参照 | `ALL` は全走査＝赤信号 |
| **`possible_keys`** | 使える**候補**の index | ここに index 名があるのに `key` が NULL＝「使えるのに使わなかった」 |
| **`key`** | 実際に**使った** index。`NULL` なら index 未使用 | `NULL` = フルスキャン |
| `key_len` | 使った index の**バイト長**。複合indexで何列ぶん使えたかの目安 | 複合indexの左端だけ使うと短くなる |
| `ref` | index と比較している相手（列名 or `const`） | `const` = 定数と突き合わせ |
| **`rows`** | **読むと見積もった行数**（統計からの推定・実測ではない） | 実データ件数に近い＝全走査に近い |
| `filtered` | WHERE 適用後に残ると見積もる割合(%) | 低いほど無駄読みが多い |
| **`Extra`** | 追加情報。`Using filesort` / `Using index` など。§4参照 | `Using filesort` / `Using temporary` は要注意 |

> `rows` は**推定値**。実際に読んだ行数を見たいときは `EXPLAIN` の代わりに `ANALYZE`（MariaDB）を使う（§5）。

---

## 3. `type`（アクセス方法）— 速い順

`type` は「1件の目的行に到達するのにどれだけ無駄に読むか」を表す。上ほど速い。

| type | 意味 | 速さ |
| --- | --- | --- |
| `const` / `system` | 主キーやUNIQUEに定数一致。**最大1行**を一度だけ読む | ◎ 最速 |
| `eq_ref` | JOINで、前テーブル1行につき相手を主キー/UNIQUEで1行引く | ◎ |
| `ref` | 非ユニークな index で等値一致。該当する複数行を index 経由で引く | ○ 良い |
| `range` | index の**範囲**スキャン（`BETWEEN` / `<` / `>` / `IN` / `LIKE 'x%'`） | ○ 良い |
| `index` | **index 全体**を走査（テーブル本体は読まないが index は端から端まで） | △ ALLよりマシな程度 |
| `ALL` | **フルテーブルスキャン**。全行を読む | ✗ 最遅 |

覚え方: **`ref` / `range` が出ていれば index が効いている。`ALL` が出たら index が使われていない**（＝ `key` も NULL のはず）。

---

## 4. `Extra`（追加情報）— よく出るもの

| Extra | 意味 | 良い/悪い |
| --- | --- | --- |
| `Using where` | 読んだ行を WHERE で絞り込んだ。普通に出る | 中立 |
| `Using index` | **カバリングindex**。必要な列が全部 index に入っており、テーブル本体を読まずに済んだ | ◎ 速い |
| `Using index condition` | index コンディションプッシュダウン。index段階で追加条件を評価し無駄な本体読みを減らす | ○ |
| `Using filesort` | ORDER BY を index で満たせず、**別途ソート**が必要。件数が多いと重い | △〜✗ |
| `Using temporary` | **一時テーブル**を作った（GROUP BY / DISTINCT / 複雑な ORDER BY）。重い | ✗ |

`Using filesort` は「ファイルに書く」という意味ではなく「**追加のソート処理が要る**」の意（メモリで済むこともある）。件数が少なければ問題にならないが、100万行を filesort すると致命的。

---

## 5. 推定でなく実測を見たい: ANALYZE

`EXPLAIN` の `rows` は統計に基づく**推定**。実際に読んだ行数と各段の所要時間を見たいときは MariaDB の `ANALYZE`（クエリを実際に走らせて計測する）を使う。

```sql
ANALYZE SELECT * FROM posts WHERE title LIKE '%NEEDLE%' ORDER BY id DESC LIMIT 50;
```

- `r_rows`（実際に読んだ行数）と `rows`（推定）を比べられる。推定が大きく外れていれば統計が古い（`ANALYZE TABLE posts;` で更新）。
- `r_total_time_ms` で各段の実時間が出る。

UIの `elapsed_ms`（アプリ側で測ったSQL往復時間）と併せて見ると、「どの段が時間を食っているか」まで分かる。

---

## 6. 5つの検証クエリはこう読む

`explain=1` を付けて各プリセットを叩いたとき、**何を見れば「効いている/いない」が分かるか**。`rows` の具体値はデータ件数で変わるので、注目すべきサインを示す。

### ① 基準: `?user_id=5`（index 効く）
`WHERE user_id=? ORDER BY id DESC LIMIT 50`

| 見るべき | 効いているサイン |
| --- | --- |
| `type` | `ref`（user_id の index で該当ユーザー分だけ引く） |
| `key` | `posts_user_id_foreign`（FKが張った index） |
| `rows` | そのユーザーの投稿数程度（例: 約1,000）。全件ではない |
| `Extra` | `Using where`。`Using filesort` が付くこともある（id順に並べ直すため）が、対象が数千行なら軽い |

→ `type=ALL` / `key=NULL` になったら index が効いていない。

### ② 深いOFFSET: `?page=20000`（効かない）
`ORDER BY id DESC LIMIT 50 OFFSET 999950`

| 見るべき | 遅いサイン |
| --- | --- |
| `key` | `PRIMARY`（主キー順に走査自体はする） |
| `rows` | **巨大**（捨てる約99万行 + 50 を数える） |

→ index を使っていても `rows` が莫大。**OFFSET が深いほど線形に遅くなる**のが本質。`page` を大きくするほど `elapsed_ms` が増えるのを確認する。対策はキーセットページネーション（[indexing.md 第8章](./indexing.md)）。

### ③ 部分一致LIKE: `?q=NEEDLE`（効かない）
`WHERE title LIKE '%NEEDLE%'`

| 見るべき | 遅いサイン |
| --- | --- |
| `type` | **`ALL`**（全走査） |
| `possible_keys` | **`NULL`**（title の index は候補にすら挙がらない。先頭が `%` のため） |
| `key` | `NULL` |
| `rows` | ほぼ全件（例: 約100万） |

→ title に index はあるのに `possible_keys` が NULL。「**index があっても中間一致では使えない**」の典型。

### ④ 前方一致LIKE: `?q=NEEDLE&match=prefix`（効く）
`WHERE title LIKE 'NEEDLE%'`

| 見るべき | 効いているサイン |
| --- | --- |
| `type` | **`range`**（index の範囲スキャン） |
| `key` | `posts_title_index` |
| `rows` | 前方一致する件数程度（NEEDLEは末尾に仕込むので **0〜少数**） |

→ ③と**同じ列・同じ検索語**でも、`match=prefix` にした途端 `type` が `ALL → range` に変わる。ヒット件数が0でも**一瞬で終わる**のが index の効果（対象位置を index が即座に特定できる）。

### ⑤ カテゴリ絞り込み: `?category_id=5`（低選択性）
`WHERE category_id=?`

| 見るべき | 読み方 |
| --- | --- |
| `possible_keys` | `posts_category_id_foreign`（候補には挙がる） |
| `key` | `NULL` になり得る |
| `type` | `ref`（index採用）または `ALL`（index無視）**どちらもあり得る** |

→ 10カテゴリ＝1区分が全体の約10%。**該当が多すぎて「index で1割を拾うよりフルスキャンが安い」とオプティマイザが判断**すると、`possible_keys` に index があるのに `key=NULL`・`type=ALL` を選ぶ。「使えるのに使わない」＝低選択性の症状。

---

## 7. UI表示との対応

`/posts` の EXPLAIN テーブルは、この文書の `table / type / possible_keys / key / rows / Extra` をそのまま出している。色分けの意味:

- `type` が **`ALL`** → **赤**（全走査＝遅い）
- `type` が `ref` / `range` など → **緑**（index が効いている）
- `key` が `(未使用)` 表示 → EXPLAIN 上は `key=NULL`（index を使っていない）

まず `type` の色を見て、赤なら `possible_keys` と `key` を見て「そもそも候補が無い（③）」のか「候補はあるが選ばれなかった（⑤）」のかを切り分けるのが読み方の基本。

---

## 参考リンク（公式）

- MariaDB: [EXPLAIN](https://mariadb.com/kb/en/explain/)
- MariaDB: [EXPLAIN の type / Extra 一覧](https://mariadb.com/kb/en/explain/#the-type-column)
- MariaDB: [ANALYZE statement（実測付き実行計画）](https://mariadb.com/kb/en/analyze-statement/)
- MariaDB: [Order By Optimization / filesort](https://mariadb.com/kb/en/order-by-optimization/)
