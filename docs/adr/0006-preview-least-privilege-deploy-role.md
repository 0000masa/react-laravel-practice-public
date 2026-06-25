---
status: accepted
---

# 検証環境デプロイは admin ロールを流用せず最小権限ロール + Permissions Boundary を使う

## 背景

[preview 環境](../deploy/pr-preview-environment.md)の作成/破棄は GitHub Actions が Terraform を `pull_request` トリガーで**自動実行**する。stg/prod 用には AdministratorAccess を持つ Terraform ロール（`AWS_TERRAFORM_ROLE_ARN`）が既にあり、これを流用すれば実装は楽になる。一方この既存ロールは `workflow_dispatch`（手動）+ GitHub Environment + ブランチ制約（main/develop）で守られている。

preview は per-PR の IAM タスクロールを作る必要があり、それを作るデプロイロールには `iam:CreateRole` / `PassRole` 等の IAM 書き込み権限が必要になる。

## 決定

**admin ロールを流用せず、preview 専用の最小権限 OIDC ロールを用意する。**

- **GitHub Environment `preview` 経由**で AssumeRole し、Environment 保護ルール（maintainer 承認等）でゲートする。
- IAM は **`/preview/` パス配下のロールにしか触れない**（`Resource = arn:aws:iam::<acct>:role/preview/*`）。
- **`iam:CreateRole` は Permissions Boundary 付与を条件**にする（`Condition: iam:PermissionsBoundary = <boundary ARN>`）。Boundary により per-PR ロールの実効権限に上限を掛ける。Boundary ポリシー自体を書き換える権限は付与しない。

## 考慮した代替案

- **既存の AdministratorAccess Terraform ロールを流用し、トリガー側だけ厳重化（Environment + maintainer ラベル + fork 不可）**: 実装は最小。**却下理由**: preview は PR ブランチのコードで Terraform を自動実行するため、admin だと PR 作成者が `terraform/pr-env/*.tf` を書き換えて任意の管理者権限操作を実行できる（pwn-request / 権限昇格）。トリガー制御だけでは構造的リスクが残る。リポジトリ既存の「ワークフロー専用・最小権限ロール」方針とも一致しない。

## トレードオフ / 影響

- preview デプロイロールは Terraform が多種リソース（CloudFront/ELBv2/ECS/SQS/Route53/S3/IAM/Logs）を作るため、既存の外科的な各ワークフローロールより**権限範囲は広くなる**。ただし決定的に異なるのは「**IAM は `/preview/` 配下しか触れず admin に昇格できない**」「**stg/prod の中核リソースを破壊できない**」点。
- Permissions Boundary ポリシーと `/preview/` パス運用という前提知識が増える（本ドキュメントと [docs/pr-preview-environment.md](../deploy/pr-preview-environment.md) に記載）。
