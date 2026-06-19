---
status: accepted
---

# Google Cloud 版は Cloud Run + VPCなし のコア構成にする

## 背景

AWS 版（`terraform/`）は S3 + CloudFront + ALB + ECS Fargate + RDS + SQS/EventBridge/SES を
VPC 上に構築した本格構成になっている。学習の次のステップとして Google Cloud に同等アプリ
（Laravel + Nginx / React SPA）をデプロイし直すにあたり、**まず最小の「コア構成」だけを作る**ことにした。
非同期キュー（SQS）・日次バッチ（EventBridge）・メール（SES）・キューワーカーは今回のスコープから外し、
後日 VPC / NAT Gateway を含むフル機能版を `terraform/gcp` とは別ディレクトリで作る。

## 決定

- **アプリ実行は Cloud Run（マルチコンテナ: nginx + php-fpm サイドカー）**。ECS Fargate は採用しない。
- **VPC / NAT Gateway を作らない。** Cloud Run はパブリックなアウトバウンド egress を Google 管理 IP で
  標準提供するため、外向き通信に VPC も NAT も不要。データベース接続も **Cloud SQL コネクタ
  （公開 IP + Unix ソケット `/cloudsql/<connection_name>`）** を使い、VPC を介さない。
- **データベースは Cloud SQL for MySQL 8.0**（MariaDB は Cloud SQL に無いため、最も近い MySQL を選択）。
  `db-f1-micro` / シングルゾーン / HA なし。
- **フロント配信は 外部 HTTPS LB + Cloud CDN + GCS バックエンドバケット**。
  同一 LB の URL マップで `/api/*` を Serverless NEG 経由で Cloud Run に振り分け、単一ドメイン化する
  （AWS の「CloudFront 単一入口」を踏襲）。
- **オリジン保護**は AWS の「秘密ヘッダー + ALB 403」ではなく、Cloud Run の
  **ingress = internal-and-cloud-load-balancing** で run.app 直叩きを遮断する。
- **画像配信**は LB の追加バックエンドバケット + Cloud CDN（公開 read GCS）。AWS の画像用 CloudFront 相当。
- **CI/CD は対象外**。手動 `gcloud` でビルド/デプロイし、インフラは「手作業作成 → `terraform import`」で
  コード化する学習フローを取る。

## トレードオフ / 理由

- ECS Fargate に対し Cloud Run は **VPC・NAT・ALB・サブネット・セキュリティグループが不要**で、
  構成要素が大幅に少なく安い。「ECS より単純で安い」ことの検証が今回の主目的。
- 代償として、Cloud SQL を公開 IP 経由で使う（VPC 内プライベート IP ではない）ことを受け入れる。
  プライベート IP を選ぶと VPC + Direct VPC egress / Serverless VPC Access が必須になり、no-VPC 目標と矛盾する。
  認証はコネクタ + パスワード（Secret Manager）で担保する。
- MySQL を選んだことで AWS 版（MariaDB）からの差分を最小化したが、Cloud SQL は MariaDB をサポートしない、
  という制約は将来 DB エンジンを動かしづらくする（ロックイン）ため記録しておく。

## 影響

- アプリ側に最小限の変更が必要: `config/filesystems.php` に GCS ディスク追加（Flysystem GCS アダプタ）、
  DB 接続を `DB_SOCKET`（Unix ソケット）対応にする、`FILESYSTEM_DISK=gcs` / `MAIL_MAILER=log` への切替。
- WAF（Cloud Armor）・非同期処理・バッチ・キューワーカー・OpenTelemetry トレースは未実装。フル版で追加する。
