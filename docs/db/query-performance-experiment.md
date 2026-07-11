# DB クエリ性能 学習実験（posts / categories）

## 目的

`posts` に 1万 → 10万 → 100万 件と行を増やしながら、**「index が効くクエリ」と「index を正しく張っても効かないクエリ」でAPIレイテンシとRDSのCPU/メモリ使用率がどう変わるか**を体感する。学習用フィクスチャであり、プロダクト機能ではない。

関連: [index をどこに張るべきか](./indexing.md)（判断基準と「効かないケース」の理屈）、[EXPLAIN の読み方](./reading-explain.md)（`explain=1` の各値の意味と5パターンの読み解き）。

---

## 全体像

| 要素 | 内容 |
| --- | --- |
| 対象テーブル | `posts`（新規・学習用）、`categories`（新規・10件マスタ）、`users`（既存・1,000人） |
| マスタ投入 | `categories`（10件）は `CategorySeeder`（冪等）→ `php artisan db:seed`（`command_type=seed`）で入る |
| データ投入 | 投稿は専用 Artisan コマンド `bench:seed --count=N`（追加式）を `db-task.yml` の `command_type=shell` で起動 |
| 検証API | `GET /api/posts`（`auth:web`）1本。クエリパラメータで5パターンを切替。`explain=1` で計装 |
| 補助API | `GET /api/categories`（`auth:web`）— UIのプルダウン用 |
| 学習UI | `/posts` ページ（React）。5プリセット＋入力欄で叩き、`elapsed_ms`/EXPLAIN/一覧を表示 |
| 負荷生成 | k6 / Distributed Load Testing on AWS（別途用意。UIは対話確認用） |
| 実行環境 | stg RDS（`db.t4g.micro` / MariaDB 11.4 / 1GB RAM / gp3 20GB） |
| 測定 | 単発は `?explain=1` + `curl -w`、CPU/メモリは持続負荷中の CloudWatch |

---

## スキーマ

```
categories
  id            bigint PK
  name          varchar
  timestamps

posts
  id            bigint PK
  user_id       FK -> users(id)        INDEX（constrained）
  category_id   FK -> categories(id)   INDEX（constrained）
  title         varchar(255)           INDEX（前方一致で効く／中間一致で効かない対比用）
  body          text                   （index なし。行サイズ稼ぎ）
  created_at / updated_at timestamps
```

- `user_id` は本物のFK。`posts` を投入する前に users を 1,000 人用意する。
- `category_id` は10件マスタへのFK。1カテゴリ約10万件（100万件時）＝**低選択性**。
- `title` にあえてindexを張り、「indexがあるのに中間一致LIKEでは使われない」を見せる。
- データ生成は **Faker**（実務同様バラつかせる）。100万件は必ず**チャンク生成→バルクINSERT**でメモリ一定に。`title` の一部に既知語 `NEEDLE` を仕込むと `LIKE '%NEEDLE%'` のヒット件数を制御できる。

---

## 検証API: `GET /api/posts`

`auth:web` 配下。既定は `ORDER BY id DESC` の `paginate(50)`。パラメータで内部SQLが変わる。

| パラメータ | 例 | 内部SQL | 検証 |
| --- | --- | --- | --- |
| `user_id` | `?user_id=5` | `WHERE user_id=? ORDER BY id DESC LIMIT 50` | 基準（index効く） |
| `page` | `?page=20000` | `... LIMIT 50 OFFSET 999950` | 深いOFFSET（効かない） |
| `q` | `?q=NEEDLE` | `WHERE title LIKE '%NEEDLE%'` | 部分一致LIKE（効かない） |
| `q`+`match` | `?q=NEEDLE&match=prefix` | `WHERE title LIKE 'NEEDLE%'` | 前方一致LIKE（効く） |
| `category_id` | `?category_id=5` | `WHERE category_id=?` | 低選択性（index無視されがち） |

**計装（`explain=1`、stg限定の opt-in）**: 通常は実務同様 `{ posts[], pagination{} }` のみ返す。`?explain=1` を付けたときだけ `elapsed_ms`（サーバ側SQL実行時間）と `EXPLAIN` 結果を追加する。

```json
{ "posts": [...], "pagination": {...}, "elapsed_ms": 812.4, "sql": "select ...", "explain": [ {"type":"ALL","key":null,"rows":998321,"Extra":"Using filesort"} ] }
```

---

## データ投入: `php artisan bench:seed`

| オプション | 動作 |
| --- | --- |
| `--count=N` | posts を N件**追加**する（追加式）。users が未作成なら先に1,000人作り、categories は `CategorySeeder` を冪等に呼んで用意する |
| `--fresh` | posts を truncate してやり直す（categories/users は保持） |

> マスタ `categories` の正は `database/seeders/CategorySeeder.php`（`DatabaseSeeder` から呼ばれる）。`php artisan db:seed`（`command_type=seed`）でも入るし、`bench:seed` も同じ Seeder を呼ぶので二重管理にならない。

追加式なので `--count=10000` → 測定 → `--count=90000`（計10万）→ 測定 → `--count=900000`（計100万）→ 測定、で3つの測定点を通過する。一気に `--count=1000000` も可。

**GitHub Actions からの起動**（`.github/workflows/db-task.yml`、既存を変更せず）:
- `command_type = shell`
- `shell_command = php artisan bench:seed --count=1000000`
- run-name に件数が残るので履歴で追える。

> ⚠️ これは状態変更（stg DBへ書き込み）。ワークフロー起動はユーザーが行う（Claudeは提案まで）。

---

## 測定手順

### 1. 単発レイテンシ（レコード数 vs 所要時間）

DBが暇なときに単発で叩き、`10k / 100k / 1M × 各パターン` を表にする。

- サーバ側SQL時間: `GET /api/posts?...&explain=1` の `elapsed_ms`
- HTTP往復: `curl -w '%{time_total}\n' -o /dev/null -s -b <cookie> '.../api/posts?...'`
- 認証: 先に `POST /auth/login` でセッションcookieを取得して付与（実務同様）

### 2. RDSのCPU/メモリ（持続負荷）

CloudWatchは1分粒度なので、k6等で**2〜3分の持続負荷**をかけた窓を見る。

観測メトリクス（`AWS/RDS`）:
- `CPUUtilization` — CPU使用率
- `FreeableMemory` — 空きメモリ（減っていく）
- `CPUCreditBalance` / `CPUCreditUsage` — **t4gバースト型のクレジット枯渇**（持続負荷で見える限界）
- `DatabaseConnections` / `ReadIOPS` / `ReadLatency`

スロークエリ: 1秒超は `/slowquery` ロググループに自動収集済み → Logs Insights で集計（`# Query_time:` を含む行）。深いOFFSET/部分一致LIKEは1秒を超えやすく、自動で捕まる。

### 注意（stg = db.t4g.micro）

- 持続負荷で **CPU>90% / FreeableMemory<256MiB アラームが実際に発火**しSNS通知が飛ぶ（＝自作監視が火を噴くのを体験できる。想定内）。
- CPUクレジット枯渇によるスロットリングは「レコード増加による遅延」とは別要因。単発レイテンシ測定は**DBが暇なとき**に行い、負荷測定と分けること。
- 共有のstgアプリに一時的な影響が出る。

---

## 実装チェックリスト（バックエンド → フロント）

- [ ] マイグレーション: `categories`、`posts`（FK/index込み）
- [ ] モデル: `Category`、`Post`（`belongsTo` 関係）
- [ ] `CategorySeeder`（区分マスタの正）＋ `DatabaseSeeder` から呼び出し
- [ ] Artisan コマンド `bench:seed`（`--count` / `--fresh`、チャンクバルクINSERT、users 準備＋`CategorySeeder` 呼び出し）
- [ ] `GET /api/posts`（パラメータ分岐＋`explain=1` 計装）、`GET /api/categories`
- [ ] ルート登録（`routes/api.php`、`auth:web` 配下）
- [ ] フロント `/posts` ページ（5プリセット＋入力欄＋メトリクス/EXPLAIN/一覧表示、`UserList.tsx` が手本）
- [ ] `App.tsx` ルート追加、`Layout.tsx` ナビ追加
- [ ] 測定 → 結果を本ドキュメントに追記（表・グラフ）
