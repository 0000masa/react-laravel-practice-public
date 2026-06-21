---
status: accepted
---

# Artifact Registry は Terraform 非管理（data 参照）にする

## 背景

このプロジェクトの GCP インフラは原則「コンソールで手動作成 → `terraform import` でコード化」で、
ほぼ全リソースを Terraform 管理下に置いている。Artifact Registry のリポジトリ（nginx / laravel）も
当初は `resource "google_artifact_registry_repository"` + import ブロックで管理していた。

## 決定

AR リポジトリは **`data "google_artifact_registry_repository"` で参照するだけ（Terraform 非管理）** にする。
import ブロックは削除し、リポジトリへの IAM 付与（push SA への `artifactregistry.writer`）だけは
Terraform で管理し続ける（data 参照のリポジトリに対する `*_iam_member` は問題なく管理できる）。
タグ不変（immutable tags）はレジストリ側＝コンソールで設定する（非管理のため Terraform では設定不可）。

## 考慮した代替案

- **Terraform 管理（resource + import）のまま**: 全体の import 規約とは一貫するが、
  レジストリのライフサイクルが app インフラの apply に結合する。**却下理由**: 下記の利点を取った。

## トレードオフ / 理由

- **ライフサイクルの分離**: レジストリは「app インフラより先に存在し、先にイメージが入っている」べき土台。
  app インフラの apply サイクルから外すのが素直。
- **単一スタックの鶏卵回避**: 同一スタックで「空 AR 作成 → push → Cloud Run 作成」を一度の apply で行うと
  image 不在で Cloud Run 作成が失敗しうる。data 参照ならこの順序依存が原理的に消える。
- **AWS との一貫性**: AWS 版は ECR を `data "aws_ecr_repository"` 参照（Terraform 外で作成）にしている。
  GCP も揃える。ドメインとイメージレジストリを stg/prod で共有する方針（[CONTEXT.md](../../CONTEXT.md) の「環境」）とも整合。

## 影響

- **data 参照は plan 時に読まれる**ため、AR リポジトリは**最初の `terraform plan` より前に存在必須**
  （無いと plan が失敗）。コンソールでの AR 作成（手順3）を terraform 実行より前に行う。
- AR だけが「コンソール作成 → import」規約から外れる（他リソースは import）。この非対称は本 ADR で説明する。
- タグ不変の担保はコンソール設定に依存する（Terraform では強制できない）。
