# DB index をどこに張るべきか

対象 DB: Amazon RDS for **MariaDB 11.4**（ストレージエンジンは InnoDB）。
このドキュメントは「index を張る/張らないをどう判断するか」を、本プロジェクトの `users` / `qr_codes` テーブルを題材に整理したもの。

---

## 1. index とは（1分で）

index は、ある列の値を **あらかじめ並べ替えて保持した検索用の木構造（InnoDB では B+Tree）**。
テーブル本体とは別に、その列を昇順で並べたデータを裏で持つ。

| index なし | index あり |
| --- | --- |
| 目的の行を探すのに**全行を上から順に確認**（フルスキャン、O(n)） | 木をたどって**該当箇所へ直接**到達（O(log n)） |
| `ORDER BY` は**全行を取り出してからソート**（filesort） | index の並び順をそのまま使うのでソート不要になり得る |

100万行での差は「数百 ms のフルスキャン」対「数 ms の木探索」レベルになり得る。ここがこのプロジェクトの検証テーマ。

InnoDB では **主キー（PRIMARY KEY）自体が index**（クラスタ化index）で、テーブル本体が主キー順で物理的に並ぶ。`id` での検索が常に速いのはこのため。

---

## 2. 判断の起点：index はクエリの4か所のために張る

「この列にindexが要るか？」は列単体では決められない。**その列が SQL のどこで使われるか**で決まる。候補になるのは次の4か所。

| SQL の場所 | 例 | index が効く理由 |
| --- | --- | --- |
| `WHERE` の絞り込み | `WHERE user_id = 5` | 該当行へ直接ジャンプできる |
| `JOIN ... ON` の結合キー | `ON qr_codes.user_id = users.id` | 結合相手を1件ずつフルスキャンせずに引ける |
| `ORDER BY` の並べ替え | `ORDER BY created_at DESC` | index の並び順を使えれば filesort を回避 |
| `GROUP BY` の集約キー | `GROUP BY status` | 同じ値がindex上で隣接し集約が速い |

逆に、**どのクエリでも WHERE/JOIN/ORDER BY/GROUP BY に出てこない列**は、いくら大きくても index を張る意味がない（例: `data`, `avatar_url` のような表示専用列）。

### 選択性（cardinality）も見る

index が効くのは「絞り込んだ結果が全体の一部」のとき。値の種類が少ない列（低選択性）は index を張っても効きにくい。

| 列の例 | 値の種類 | index の効き |
| --- | --- | --- |
| `id`, `email` | ほぼ全行がユニーク（高選択性） | よく効く |
| `user_id` | ユーザー数ぶん | 中〜高。効く |
| `status`（pending/completed/failed の3値） | 3種類（低選択性） | 単体では効きにくい。「completed が99%」なら status=pending の検索にだけ効く |

---

## 3. created_at など「時刻列」に index を張るべきか

結論: **無条件ではない。「その時刻列を WHERE の範囲検索か ORDER BY に使うか」で決まる。**

| その列の使われ方 | index を張るべきか |
| --- | --- |
| `ORDER BY created_at DESC` で一覧を並べる | **張る価値が高い**（filesort を消せる） |
| `WHERE created_at >= ? AND created_at < ?`（期間集計・日次バッチ） | **張る価値が高い**（範囲スキャンが効く） |
| 画面に日時を表示するだけ。検索も並べ替えもしない | 張らない（無駄なコスト） |

本プロジェクトの `GET /qrcodes` と `GET /users` は、両方とも
```sql
... ORDER BY created_at DESC LIMIT 50 OFFSET ?
```
を実行している。**`created_at` に index がないため、50件だけ欲しくても毎回テーブル全行を取り出してソートしている**（`EXPLAIN` の `Using filesort`）。これが「レコードが増えると一覧APIが遅くなる」直接の原因。

> 補足: このプロジェクトの一覧は「投稿された順（時系列）」で並べたいだけなので、`created_at` の代わりに **主キー `id` で `ORDER BY id DESC`** しても実用上ほぼ同じ並びになり、`id` は既に主キーindexなので追加コストゼロで filesort を消せる。「時刻列にindexを足す」か「idソートに変える」かは設計判断（→ 検証で両方試すと学びになる）。

---

## 4. index はタダではない（張りすぎの害）

index は読み取りを速くする代わりに、次のコストを常に払う。

| コスト | 内容 |
| --- | --- |
| 書き込みが遅くなる | `INSERT` / `UPDATE` / `DELETE` のたびに、対象列の index も**全部更新**する。index 5本なら書き込み1回で木を5回いじる |
| ストレージ増 | index は実データとは別に容量を食う |
| オプティマイザの迷い | 似たindexが乱立すると、MariaDB が最適なindexを選び損ねることがある |

そのため原則は「**そのクエリで実測して遅い所にだけ張る**」。「念のため全列に張る」は書き込み負荷とストレージを無駄に増やすアンチパターン。

この検証（1万→10万→100万件でINSERTしていく）では、**index を増やすほど Seeder の INSERT 自体も遅くなる**ことも同時に観測できる（読み取りを速くする代償が書き込みに出る、というトレードオフの体感）。

---

## 5. 複合 index と「左端プレフィックス」

複数列をまとめて1本にする index を複合index（composite index）という。列の**順序**が重要。

例: `INDEX (user_id, created_at)` を張った場合、この1本が効くクエリは:

| クエリ | 効くか | 理由 |
| --- | --- | --- |
| `WHERE user_id = 5 ORDER BY created_at DESC` | ◎ 効く | 左端 `user_id` で絞り、その中は `created_at` 順に並んでいる |
| `WHERE user_id = 5` | ○ 効く | 左端だけ使う |
| `WHERE created_at >= ?`（user_id 指定なし） | ✗ 効かない | 左端の `user_id` を飛ばして2列目だけは使えない（左端プレフィックス規則） |

「特定ユーザーのQRコードを新しい順に」という検索をするなら `(user_id, created_at)` の複合index が最適。列の順序は「まず等値で絞る列 → 次に範囲/並べ替えの列」が基本。

---

## 6. このプロジェクトの現状 index 棚卸し

### users
| 列 | index | 種別 |
| --- | --- | --- |
| `id` | あり | 主キー（クラスタ化） |
| `email` | あり | UNIQUE |
| `google_id` | あり | UNIQUE |
| `created_at` | **なし** | `GET /users` が ORDER BY している → 候補 |

### qr_codes
| 列 | index | 種別 |
| --- | --- | --- |
| `id` | あり | 主キー（クラスタ化） |
| `user_id` | あり | FK（`constrained()` が自動生成） |
| `created_at` | **なし** | `GET /qrcodes` が ORDER BY している → 候補 |
| `status` | **なし** | 低選択性。今のAPIは絞り込んでいないので不要 |

**張る候補（この検証で効果を測る対象）**
- `qr_codes.created_at` に単一index、または `id` ソートへの変更 → 一覧APIの filesort 解消
- 「ユーザー別一覧」を作るなら `qr_codes (user_id, created_at)` の複合index

Laravel マイグレーションでの書き方:
```php
// 単一
$table->index('created_at');
// 複合
$table->index(['user_id', 'created_at']);
```

---

## 7. 効いているかの確認方法：EXPLAIN

> 各列・各値の詳しい読み方と、検証5パターンごとの読み解きは [reading-explain.md](./reading-explain.md) に独立してまとめてある。ここは要点のみ。

index を張る/張らないの判断は、必ず `EXPLAIN` で実際の実行計画を見て決める（勘で張らない）。

```sql
EXPLAIN SELECT * FROM qr_codes ORDER BY created_at DESC LIMIT 50;
```

見るべき列:

| EXPLAIN の項目 | 良くない値 | 良い値 |
| --- | --- | --- |
| `type` | `ALL`（フルスキャン） | `ref` / `range` / `eq_ref` / `const` |
| `key` | `NULL`（indexを使っていない） | 使われた index 名 |
| `rows` | 実データ件数に近い（全行読む） | 小さい |
| `Extra` | `Using filesort` / `Using temporary` | それらが消える |

この検証では **index を張る前後で同じクエリを `EXPLAIN` し、`type: ALL → range`、`Using filesort` が消える**のを確認するのがゴール。所要時間だけでなく実行計画で裏が取れる。

---

## 8. index を正しく張っても効かない/効きにくいクエリ

index は「張り忘れ」だけが問題ではない。**張ってあるのに、クエリの形やデータの分布のせいで使われない**ことがある。実務でDBが遅い原因の多くはこちら。本リポの学習用 `posts` テーブル（`docs/db/query-performance-experiment.md` 参照）で、次の3類型を `GET /api/posts` のパラメータ違いとして観測できる。

| 類型 | SQL（posts） | なぜ効かない | 叩き方 | 対策 |
| --- | --- | --- | --- | --- |
| 深い OFFSET | `ORDER BY id LIMIT 50 OFFSET 999950` | `id` のindexはあるが、**捨てる99万行を先頭から数える**必要がある。OFFSETが深いほど線形に悪化 | `?page=20000` | キーセットページネーション（`WHERE id < ? ORDER BY id DESC LIMIT 50`）。「前の続き」をindexで一発検索 |
| 前方ワイルドカード LIKE | `WHERE title LIKE '%NEEDLE%'` | B-Tree indexは**左端から一致**しか使えない。先頭が `%` だと開始位置が定まらず**全走査** | `?q=NEEDLE`（既定 `match=partial`） | FULLTEXT index、前方一致（`'NEEDLE%'`）に変える、専用の検索エンジン（OpenSearch等） |
| 低選択性フィルタ | `WHERE category_id = 5`（10種・各約10%） | 該当が全体の1割もある。**index経由で1割を拾うよりフルスキャンの方が安い**とオプティマイザが判断し、indexを無視 | `?category_id=5` | 低選択性の列は単体indexが効きにくい。他の高選択性条件と複合index、または絞り込み自体を見直す |

対比として、**同じ `GET /api/posts` でも index がよく効く**のがこれ:

| 効く例 | SQL | 理由 | 叩き方 |
| --- | --- | --- | --- |
| ユーザー絞り込み | `WHERE user_id = 5 ORDER BY id DESC LIMIT 50` | 1,000ユーザーに分散＝**高選択性**。`user_id` のindexで該当ユーザー分（約1,000件）だけ引ける | `?user_id=5` |
| 前方一致 LIKE | `WHERE title LIKE 'NEEDLE%'` | 先頭が固定文字なので**index の範囲スキャン**が使える | `?q=NEEDLE&match=prefix` |

学びの要点: **「同じテーブル・同じendpointでも、パラメータ次第で1msにも1秒にもなる」**。これは `EXPLAIN`（第7章）で `type: range/ref`（効く）と `type: ALL` + `Using filesort`（効かない）の違いとして裏が取れる。

## 参考リンク（公式）

- MariaDB: [Getting Started with Indexes](https://mariadb.com/kb/en/getting-started-with-indexes/)
- MariaDB: [EXPLAIN](https://mariadb.com/kb/en/explain/)
- MariaDB: [Order By Optimization / filesort](https://mariadb.com/kb/en/order-by-optimization/)
- MariaDB: [Compound (Composite) Indexes](https://mariadb.com/kb/en/compound-composite-indexes/)
- Laravel 12: [Migrations — Indexes](https://laravel.com/docs/12.x/migrations#indexes)
