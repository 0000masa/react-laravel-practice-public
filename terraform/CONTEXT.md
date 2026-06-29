# AWS インフラ

React SPA + Nginx + Laravel を S3 + CloudFront + ALB + ECS + RDS で配信する本番相当の構成（`terraform/stg/` がルート、`terraform/modules/app-infrastructure/` が実体）。用語の正は同モジュールの `.tf`。

## Language

**検証環境（preview 環境）**:
PR ごとに専用サブドメイン `pr-<n>.preview.<domain>` へ立ち上げる、その PR のコードで動く使い捨ての本番相当フルスタック。`preview` ラベルで作成、PR クローズ/ラベル除去で破棄する。詳細は [docs/pr-preview-environment.md](../docs/deploy/pr-preview-environment.md)。
_Avoid_: ステージング（stg は常設の共有環境で別物）、レビューアプリ

**preview ユーザー**:
共通 RDS 上で検証環境が使う MySQL ユーザー。`GRANT ALL ON \`preview\_%\`.*` を持ち、`preview_pr<n>` database を自身で作成/削除できる。stg 本体の database には触れない。
_Avoid_: master ユーザー、アプリユーザー

**スロット（slot_a / slot_b）**:
本番 web サービスの ECS ネイティブ Blue/Green 切替に使う 2 つのターゲットグループ。検証環境では Blue/Green を使わないため登場しない。
_Avoid_: 検証環境のターゲットグループ（そちらは `preview-pr<n>-tg`）

**preview の閲覧ドメイン（`preview_zone_apex`）**:
ブラウザがアクセスする preview のホスト名の親。`preview.<domain>`（例 `preview.mylabinfra.com`）で、各 PR は `pr-<n>.preview.<domain>`。CloudFront/ACM/WAF の対象。**メールの送信元ドメインとは別物**。
_Avoid_: メール送信元ドメイン、SES 検証ドメイン

**メール送信元ドメイン（SES 検証ドメイン）**:
SES で検証済みの唯一のドメイン `${sub_frontend_domain_name}.<domain>`（例 `stg.www.mylabinfra.com`）。preview は独自ドメインを SES 検証せず、From をこの検証済みドメイン（`noreply@stg.www.<domain>`）に向けて送る。preview の閲覧ドメイン（`preview.<domain>`）は SES 未検証なので From に使えない。
_Avoid_: preview の閲覧ドメイン、`preview_zone_apex`

**マネージド WAF（`cloudfront_waf`）**:
全環境（prod / stg / preview）共通の CloudFront 用 Web ACL。AWS マネージドルール（攻撃遮断）を担う。役割は「攻撃遮断」であって「アクセス制限（誰が入れるか）」ではない。WAF は全環境で1枚に集約する。
_Avoid_: Basic 認証 WAF（Basic 認証は WAF ではなく CloudFront Function で行う）

**Basic 認証（アクセス制限）**:
stg / preview を外部非公開にするためのアクセス制限。WAF ではなく **CloudFront Function**（`spa_fallback` 関数に差し込む）で行い、`enable_basic_auth` で環境ごとに ON/OFF する（prod は false＝公開）。資格情報は SSM の生 `user:pass` を apply 時に関数へ焼き込む。
_Avoid_: WAF Basic 認証、マネージド WAF（攻撃遮断とは別概念）

**ログのホット層 / コールド層**:
ECS のログ（ロググループ `/ecs/${project_name}`）を保持期間で2層に分ける考え方。**ホット層** = CloudWatch Logs に直近30日。Logs Insights で即検索でき、日常の障害調査に使う。**コールド層** = そこから Firehose で S3 に退避し、Glacier Instant Retrieval 中心に1年保管する監査・長期保管用。通常は読まず、必要時に Athena 等で読む。stg/prod 共有モジュール側の仕組みで、preview には無い。設計は [docs/monitoring/cloudwatch-logs-s3-archival.md](../docs/monitoring/cloudwatch-logs-s3-archival.md)、方式判断は [ADR 0011](../docs/adr/0011-cloudwatch-logs-archive-via-firehose.md)。
_Avoid_: バックアップ（DB バックアップとは別物）、エクスポートタスク方式（`CreateExportTask` は不採用）
