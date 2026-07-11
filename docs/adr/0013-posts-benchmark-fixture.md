---
status: accepted
---

# DB性能学習用に posts / categories テーブルと GET /api/posts を追加する

## 背景

「レコードを 1万→10万→100万 と増やすと、API のレイテンシと RDS の CPU / メモリ使用率がどう変わるか」を体感するための学習環境が欲しい。特に **index を正しく張っても遅くなるクエリ（深い OFFSET / 中間一致 LIKE / 低選択性フィルタ）** と、index がよく効くクエリを対比したい。

既存の `qr_codes` テーブルを流用する案もあったが、次の理由で不適だった:

- `qr_codes` は S3 上の QR 画像の存在を前提にした行。ダミーを大量投入すると「画像なしのレコード」が本物データに混ざる。
- LIKE 検証に向くテキスト列がない（`data` は QR の元文字列）。

そのため、**プロダクト機能ではない学習用フィクスチャ**として新しいテーブルと API を足す。将来コードを読む人が「この `posts` は何の機能？」と迷わないよう、意図をここに残す。

## 決定

- `posts`（`user_id` FK / `category_id` FK / `title`(index) / `body` / timestamps）と `categories`（10件マスタ）を新設する。`users` は 1,000 人に分散させ `WHERE user_id=?` を高選択性にする。
- 投入は Artisan コマド `bench:seed --count=N`（追加式・チャンクバルク INSERT）。GitHub Actions からは既存 `db-task.yml` の `command_type=shell` で叩き、**ワークフローは変更しない**。
- 検証 API は `GET /api/posts` 1本（`auth:web` 配下）。`user_id / category_id / q / match / page` のパラメータで5つのクエリパターンを切替え、`explain=1`（opt-in）で `elapsed_ms` と `EXPLAIN` を返す。プルダウン用に `GET /api/categories` も追加。
- フロントに学習用ページ `/posts` を追加（プリセット＋入力欄で叩き、所要時間と実行計画を目視する）。負荷生成は別途 k6 / Distributed Load Testing on AWS が担い、この UI は対話的な確認用。

設計と測定手順の詳細は [docs/db/query-performance-experiment.md](../db/query-performance-experiment.md)、index の理屈は [docs/db/indexing.md](../db/indexing.md)。

## 考慮した代替案

- **既存 `qr_codes` にダミー投入**。却下理由: 画像なし行の混入、LIKE 向きの列の欠如、本物データの汚染。
- **検証 API を認証なしにする**。却下理由: 「認証ありの API を curl で叩く」実務に寄せたいため `auth:web` 配下に置いた。中身は偽データの読み取り専用なので露出リスクは低いが、prod には出さず stg 限定で使う。
- **title/body を Faker で realistic に生成する**。当初は実務の多様性を優先して Faker を採用したが、seed を叩く runner イメージは `composer install --no-dev` でビルドされ **Faker（`require-dev`）が無い**ため `Call to undefined function fake()` で落ちた。**runner で動くコマンドが dev 専用依存を持つのは設計として誤り**と判断し、単語プールからの自前生成に変更（users も `factory()` をやめてバルク INSERT）。文章の自然さは測定対象のDB性能に影響しないため許容。

## トレードオフ / 影響

- stg（`db.t4g.micro`）で持続負荷をかけると、既存の CPU>90% / FreeableMemory<256MiB アラームが発火し SNS 通知が飛ぶ。これは想定内（自作監視の発火を体験する）だが、共有の stg アプリに一時的な影響が出る。
- `posts` / `categories` はプロダクト機能ではない。マイグレーションとして常設されるため、本番運用に載せる場合は投入データの扱い（学習後の truncate 等）を別途判断する。
