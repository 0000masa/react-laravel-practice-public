---
status: accepted
---

# preview 共有リソースは stg ルートに置き、共有モジュールは preview 非依存に保つ

## 背景

アプリ基盤の Terraform は `terraform/modules/app-infrastructure/`（stg/prod 共通の実体）と、それを呼ぶ環境別ルート（`terraform/stg/`、将来の `terraform/prod/`）に分かれている。[preview 環境](../deploy/pr-preview-environment.md)は stg に相乗りする形で作られ、その「共有 / ブートストラップ」リソース（`*.preview.<domain>` のワイルドカード ACM、Basic 認証 WAF、`api.preview`→ALB レコード、preview デプロイ用 OIDC ロール、Permissions Boundary）を `preview_shared.tf` に定義している。

このファイルは当初**共有モジュール内**に置かれていた。だが preview は stg 専用で prod には不要なため、共有モジュールに置くと prod ルートがモジュールを呼んだだけで preview 用リソースまで生えてしまう。さらに `preview_db_password` の SSM 読み取り権限が共有 ECS 実行ロールのポリシー（モジュール内）に直接混ざっており、prod ではこの SSM パラメータが存在せず `plan` が失敗する。preview の関心がモジュールへ染み出していた。

## 決定

**`preview_shared.tf` を共有モジュールから `terraform/stg/` ルートへ移し、共有モジュールは preview を一切知らない状態に保つ。**

- `preview_shared.tf` の全リソースと SSM データソース（`preview_basic_auth` / `preview_db_password`）、preview 系 output、`preview_github_environment_name` 変数を `terraform/stg/` へ移す。prod ルートはモジュールを呼ぶだけで、preview リソースは**コード上に存在しない**。
- 共有 ECS 実行ロールへの `preview_db_password` 読み取り付与はモジュールから外し、**stg ルート側で実行ロールに追加ポリシーとして後付け**する（モジュールの実行ロールポリシーは preview を参照しない）。
- preview リソースが参照する ALB リスナー / ECS クラスタ / 実行ロール ARN 等は、pr-env が `terraform_remote_state` で読むために**既にモジュール output として公開済み**なので、ルートへの移動で追加の output プラミングはほぼ発生しない。

## 考慮した代替案

- **B: モジュール内に残し `enable_preview` フラグ（bool + `count`）で stg=true / prod=false に切り替える**。内部リソース参照をそのまま使え、`rds_config` 等と同じ「環境差は変数で表現」方針とも一貫する。**却下理由**: 必要 output が既に揃っており A の移動コストが小さいこと、そして「prod のコードに preview が物理的に存在しない」方が `count` のゲートより誤適用に強く要件を構造で保証できるため。
- **C: preview 共有用の子モジュールに切り出し stg からだけ呼ぶ**。関心の分離は最もきれい。**却下理由**: preview 共有は ALB / ECS / 実行ロールと密結合で、子モジュール化すると結局それらを変数で渡し直す必要があり、A 以上の配線コストに見合う利点がない。

## トレードオフ / 影響

- 共有モジュールと同じ「アプリ基盤の .tf」でありながら `preview_shared.tf` だけがルートに置かれるため、初見では非対称に見える（本 ADR がその理由）。
- stg ルートがモジュールの ECS 実行ロールに**後付けでポリシーを足す**構造になる。実行ロールの権限が2か所（モジュール本体 + stg ルート）に分かれる点に注意が必要。
- 移行時、`preview_shared.tf` が未 apply のうちに移すため state 上の `moved {}` ブロックは不要。既に apply 済みの段階で移す場合は `module.app.<addr>` → `<addr>` の `moved` を一段噛ませること。
