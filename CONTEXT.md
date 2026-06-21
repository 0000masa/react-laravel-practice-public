# practice-gcp-stg インフラ

GCP（ステージング）上に React SPA + Laravel API を配信するためのインフラ構成。
コンソールで手作業作成 → `terraform import` でコード化する方針。用語の正は `terraform/gcp/` の `.tf`。

## Language

**frontend バケット**:
`practice-gcp-stg-frontend`。React SPA の静的アセット（ビルド成果物）を置く GCS バケット。
本番配信は外部 HTTPS LB のバックエンドバケット経由で行う。
_Avoid_: 静的ウェブサイトバケット（ネイティブのウェブサイトエンドポイントは本番では使わない）

**ウェブサイト公開（このバケットの文脈）**:
HTTPS LB + Cloud CDN の背後で frontend バケットを SPA オリジンとして配信すること。
GCS ネイティブの `*.storage.googleapis.com` ウェブサイトエンドポイントでの直接公開は**指さない**。
_Avoid_: 静的ウェブサイトホスティング（S3 static website hosting の連想で誤解を招く）

**バックエンドバケット**:
LB がバケットをオリジンとして扱うためのリソース（`google_compute_backend_bucket`）。
frontend / images それぞれに 1 つずつ存在し、Cloud CDN を有効化している。

**環境（stg / prod）**:
同一 GCP プロジェクト内で**名前プレフィックス**（`practice-gcp-stg-*` / `practice-gcp-prod-*`）により分ける単位。
ドメインとイメージレジストリ（Artifact Registry）は環境間で共有する。AWS 版と同じ構成。
別プロジェクトに分離する方式は採らない（ドメイン/レジストリの分離・共有設定が必要になり大規模向けのため）。
_Avoid_: プロジェクト分離（GCP プロジェクト ID は stg/prod で同一）
