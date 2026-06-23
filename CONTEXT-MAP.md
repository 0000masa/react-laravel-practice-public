# Context Map

このリポジトリは AWS（本番相当）と GCP（学習用の別構成）の 2 つのインフラ文脈を持つ。

## Contexts

- [AWS インフラ](./terraform/CONTEXT.md) — React + Nginx + Laravel を S3 + CloudFront + ALB + ECS + RDS で配信する本番相当構成（`terraform/stg/`・`terraform/modules/`）。PR ごとの検証環境もここに属する。
- [GCP インフラ(stg)](./CONTEXT.md) — 同じアプリを Cloud Run 等で配信する学習用構成（`terraform/gcp/`）。

## Relationships

- 両者は**同じアプリ（frontend / backend イメージ）を異なるクラウドに載せた並行構成**で、依存関係はない。用語の正はそれぞれの `.tf`。
