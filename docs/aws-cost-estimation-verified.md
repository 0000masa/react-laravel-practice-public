# AWS コスト見積もり（公式料金検証版）

> deploy-on-aws プラグインの AWS Knowledge MCP 経由で、AWS 公式料金ドキュメントを参照して作成した見積もり。各項目に一次情報の URL を明示。

## 概要

- **対象環境**: `terraform/stg/`（`modules/app-infrastructure/` モジュール使用）
- **リージョン**: ap-northeast-1（東京）／ CloudFront・WAF と frontend 証明書のみ us-east-1
- **料金取得日**: **2026-05-11**（前回 2026-04-21 から更新）
- **料金ソース**: AWS 各サービス公式 pricing ページを AWS Knowledge MCP で取得（URL は各節末に記載）
- **通貨**: USD（税抜、日本消費税は別途）
- **シナリオ**: **RPS（リクエスト毎秒）ベース** で低・中・高の 3 種類を試算
- **ECS 起動タイプ**: `FARGATE_SPOT`（コード上の設定）。Spot は最大 70% OFF / 実勢 50–65% OFF で変動。**OnDemand 比較値も併記**。

## トラフィックシナリオ定義（RPS ベース）

`backend/`（Laravel 12 + nginx + php-fpm、混合エンドポイント）の 1 タスク（1 vCPU / 2 GB / php-fpm 5 worker 想定）の安定処理能力は **30–50 RPS** と推定。autoscale 閾値 CPU 60% / Memory 70%（`ecs_web.tf`、min 1 max 6）を考慮して下記を定義する。

| シナリオ | RPS レンジ | 平均 main タスク数 | 月間 API リクエスト数 | 想定 |
|---|---|---|---|---|
| **低** | 1–40 RPS（平均 5 RPS） | 1 | ~13 M | 開発/ステージング通常運用、autoscale 未発動 |
| **中** | 40–150 RPS（平均 75 RPS） | 2.5（時間加重平均） | ~196 M | 商用想定、autoscale 発動、混合トラフィック |
| **高** | 150–300 RPS（平均 250 RPS） | 6（max 張り付き） | ~657 M | ピーク持続。300 RPS 超過なら `max_capacity` 引き上げ推奨 |

> RPS は ALB（API）への到達リクエスト基準。CloudFront 配下のフロントエンドアセットはキャッシュヒット率が高く、別計上。

## 計算前提（Assumptions）

| 項目 | 値 | 根拠 |
|---|---|---|
| ECS main タスク | 1 vCPU / 2 GB（FARGATE_SPOT） | `modules/app-infrastructure/ecs_web.tf` |
| ECS main サイドカー | log-router + adot-collector（task 内 1024 CPU / 2048 MB 配分内、追加課金なし） | `ecs_web.tf` |
| ECS queue worker | 0.25 vCPU / 0.5 GB（FARGATE_SPOT）× 1 タスク常時稼働 | `ecs_queue.tf` |
| Autoscale main | min 1 / max 6（CPU 60%、Memory 70%） | `ecs_web.tf` |
| migration / seeder | 月 10 回 × 5 分（0.25 vCPU / 0.5 GB） | 運用想定 |
| daily-report バッチ | 日次 1 回 × 3 分（0.25 vCPU / 0.5 GB） | `event_bridge.tf` |
| RDS | db.t4g.micro / 20 GB gp3 / Single-AZ / `backup_retention_period = 0` | `rds.tf` |
| S3 ストレージ | frontend ~200 MB、images ~5 GB | ビルド成果物 + QR 画像想定 |
| CloudFront 転送量 | フロントエンドアセット（キャッシュヒット率高）。低 ~200 GB / 中 ~600 GB / 高 ~2 TB | 低/中は無料枠 1 TB 内 |
| CloudWatch Logs | 30 日保持、低 5 GB / 中 30 GB / 高 100 GB の月間取り込み | `cloudwatch.tf`, FireLens 収集、RPS 比例 |
| WAF | 月リクエスト 低 1 M / 中 3 M / 高 15 M（CloudFront 経由のフロントエンドのみ） | `waf.tf`、API は非経由 |
| SES | 月 低 1,000 / 中 5,000 / 高 20,000 通 | エラー通知 + バッチレポート |
| SQS | 月 低 0.1 M / 中 1 M / 高 5 M リクエスト | QR 非同期キュー、RPS 比例 |
| NAT Gateway | 1 台、月処理データ 低 30 GB / 中 100 GB / 高 300 GB | `single_nat_gateway = true`、外部 API・ECR・Logs 経路 |
| ALB 公開 IPv4 | 2 アドレス（2 AZ） | 2024-02 以降の課金対象 |

---

## サービス別見積もり

### 1. ECS on Fargate / Fargate Spot（コンピュート）

- **構成**: `modules/app-infrastructure/ecs_web.tf` / `ecs_queue.tf` / `ecs_tasks.tf` / `event_bridge.tf`
- **公式料金**:
  - Linux/X86 Fargate は vCPU-秒 と GB-秒 で課金、最低 1 分。Savings Plans で最大 50%、**Fargate Spot で最大 70%** 割引（実勢 50–65%）。
  - 課金は「コンテナイメージ pull 開始 → タスク終了」まで秒単位、最低 1 分。
- **ap-northeast-1 オンデマンド単価**:
  - vCPU: **$0.05056 / vCPU-時間**
  - メモリ: **$0.00553 / GB-時間**
- **Fargate Spot 公称単価**（公式 70% OFF ベースライン、実勢は供給により変動）:
  - vCPU: **$0.01518 / vCPU-時間**
  - メモリ: **$0.00166 / GB-時間**

#### シナリオ別月額（FARGATE_SPOT ベース、括弧内はオンデマンド換算）

| タスク | 計算（Spot） | 低 | 中 | 高 |
|---|---|---|---|---|
| main（1 vCPU / 2 GB） | `(1×0.01518 + 2×0.00166) × 730 × N` | 1 台: **$13.50** ($44.98) | 2.5 台: **$33.74** ($112.45) | 6 台: **$80.97** ($269.88) |
| queue worker（0.25 vCPU / 0.5 GB） | `(0.25×0.01518 + 0.5×0.00166) × 730` | **$3.38** ($11.25) | **$3.38** ($11.25) | **$3.38** ($11.25) |
| migration / seeder（月 10 回 × 5 分） | 微小 | $0.004 | $0.004 | $0.004 |
| daily-report（30 回/月 × 3 分） | 微小 | $0.007 | $0.007 | $0.007 |
| **ECS 小計（Spot）** | | **≈ $16.89** | **≈ $37.13** | **≈ $84.37** |
| 同（OnDemand 比較） | | ($56.23) | ($123.70) | ($281.13) |

> Fargate Spot は中断リスクあり。実勢割引は 50–65% 程度なので、保守的に見積もる場合は OnDemand の 40–50% 程度を予算化するのが安全。Tokyo region の Spot 公称価格は AWS Fargate Pricing ページ参照。
>
> 公式: https://aws.amazon.com/fargate/pricing/

---

### 2. Amazon RDS for MariaDB

- **構成**: `modules/app-infrastructure/rds.tf`（db.t4g.micro / 20 GB gp3 / Single-AZ / `backup_retention_period = 0`）
- **公式料金**（要点）:
  - On-Demand 課金、最低 10 分
  - T4g/T3 は **Unlimited mode**。ベースライン超過時の CPU クレジットは全リージョン共通 **$0.075 / vCPU-時間**
  - バックアップは「allocated と同サイズまで」無料、超過分は別途
- **東京リージョン単価**: db.t4g.micro Single-AZ **$0.017/時間**、gp3 **$0.138/GB-月**

#### 月額計算（全シナリオ共通、autoscale 影響なし）

| 項目 | 計算 | 月額 |
|---|---|---|
| db.t4g.micro インスタンス時間 | `0.017 × 730` | **$12.41** |
| gp3 ストレージ 20 GB | `0.138 × 20` | **$2.76** |
| バックアップ（無効） | $0 | $0.00 |
| CPU クレジット超過（前提: ベースライン内） | – | **想定 $0** |
| **RDS 小計** | | **≈ $15.17** |

> 高トラフィック時は DB が CPU クレジットを消費する可能性あり。バーストが続くと `$0.075 × vCPU 時間` の追加課金が発生する点に留意（dashboard で監視推奨）。
>
> 公式: https://aws.amazon.com/rds/mariadb/pricing/

---

### 3. Application Load Balancer

- **構成**: `modules/app-infrastructure/alb.tf`（ALB ×1、TG ×2、Listener ×2）
- **公式料金**:
  - 稼働時間 **$0.0288/時間**（東京）
  - LCU **$0.008/LCU-時間** — 新規接続/秒、アクティブ接続/分、処理バイト、ルール評価のうち最大値で算出
  - 1 LCU = 25 conn/sec or 3,000 active conn/min or 1 GB/h（EC2/IP target）or 1,000 rule eval/sec
  - **公開 IPv4 アドレス**: $0.005/h × アドレス数（2024-02 以降）

#### シナリオ別月額

| 項目 | 計算 | 低 | 中 | 高 |
|---|---|---|---|---|
| ALB 稼働時間 | `0.0288 × 730` | $21.02 | $21.02 | $21.02 |
| LCU（new conn + processed bytes ベース） | `0.008 × LCU × 730` | 1 LCU: **$5.84** | 3 LCU: **$17.52** | 10 LCU: **$58.40** |
| 公開 IPv4 ×2 | `0.005 × 2 × 730` | $7.30 | $7.30 | $7.30 |
| **ALB 小計** | | **≈ $34.16** | **≈ $45.84** | **≈ $86.72** |

> LCU は支配次元（多くの場合「新規接続/秒」または「処理バイト」）で決まる。本見積もりは RPS から新規接続/秒を推定（HTTP/1.1 keep-alive 想定、connection reuse あり）。
>
> 公式: https://aws.amazon.com/elasticloadbalancing/pricing/

---

### 4. NAT Gateway（VPC）

- **構成**: `modules/app-infrastructure/vpc.tf`（terraform-aws-modules/vpc/aws、`single_nat_gateway = true`）
- **公式料金**: 稼働時間 + データ処理
  - 東京: **$0.062/時間** + **$0.062/GB**

#### シナリオ別月額

| 項目 | 計算 | 低 | 中 | 高 |
|---|---|---|---|---|
| 固定費 | `0.062 × 730` | $45.26 | $45.26 | $45.26 |
| データ処理 | `0.062 × GB` | 30 GB: **$1.86** | 100 GB: **$6.20** | 300 GB: **$18.60** |
| **NAT Gateway 小計** | | **≈ $47.12** | **≈ $51.46** | **≈ $63.86** |

> S3 Gateway VPC Endpoint（`vpc.tf`）により S3 トラフィックは NAT 経由ではないため非課金。外部 API（Google OAuth）、ECR pull、CloudWatch Logs 送信が主な経路。
>
> 公式: https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html

---

### 5. CloudFront

- **構成**: `modules/app-infrastructure/cloudfront.tf`（frontend + images の 2 distribution、frontend は WAF 連携、CF Function spa_fallback ×1）
- **公式料金**（2026-05-11 取得 / Japan tier）:
  - **常時無料枠**: 月 1 TB データ転送 out + 1,000 万 HTTPS リクエスト + 200 万 CF Function invocations
  - データ転送 out（Japan）: First 1 TB Free → **Next 9 TB $0.114/GB**
  - HTTPS リクエスト（Japan）: First 10 M Free → **$0.0120 / 10,000 req**
  - Origin への転送（Japan）: **$0.060/GB**
  - CF Functions: **$0.10 / 100 万 invocations**

#### シナリオ別月額

| 項目 | 低（200 GB / 5 M req） | 中（600 GB / 30 M req） | 高（2 TB / 100 M req） |
|---|---|---|---|
| データ転送 out | 無料枠内: $0 | 無料枠内: $0 | 1 TB 超過分 1024 GB × $0.114 = **$116.74** |
| HTTPS リクエスト | 無料枠内: $0 | 無料枠内: $0 | 90 M × $0.0120/10K = **$108.00** |
| Origin 転送（API キャッシュ少、frontend キャッシュ多） | ~5 GB × $0.060 = **$0.30** | ~15 GB × $0.060 = **$0.90** | ~30 GB × $0.060 = **$1.80** |
| CF Functions | 無料枠内: $0 | 無料枠内: $0 | 無料枠内: $0 |
| **CloudFront 小計** | **≈ $0.30** | **≈ $0.90** | **≈ $226.54** |

> 注: API トラフィックは ALB 直接（`api.stg.*` で Route 53 → ALB）。CF を経由するのは frontend SPA アセットと images のみ。RPS 増加時も CF アセット要求はキャッシュヒット率に依存。
>
> 公式: https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/

---

### 6. AWS WAF（CloudFront scope）

- **構成**: `modules/app-infrastructure/waf.tf`（Web ACL ×1、AWSManagedRulesCommonRuleSet ×1）
- **公式料金**（リージョン共通、プロレート）:
  - Web ACL: **$5.00/月**
  - ルール / マネージドルールグループ: **$1.00/月** ごと
  - リクエスト: **$0.60 / 100 万**

#### シナリオ別月額（WAF は frontend のみ）

| 項目 | 低（1 M req） | 中（3 M req） | 高（15 M req） |
|---|---|---|---|
| Web ACL 基本 | $5.00 | $5.00 | $5.00 |
| マネージドルールグループ ×1 | $1.00 | $1.00 | $1.00 |
| リクエスト | 1 × $0.60 = $0.60 | 3 × $0.60 = $1.80 | 15 × $0.60 = **$9.00** |
| **WAF 小計** | **≈ $6.60** | **≈ $7.80** | **≈ $15.00** |

> 公式: https://aws.amazon.com/waf/pricing/

---

### 7. Route 53

- **構成**: `modules/app-infrastructure/route53.tf`（既存ホストゾーン参照、レコード 14 件程度）
- **公式料金**: Hosted Zone **$0.50/月**（先頭 25 個まで）、クエリ **$0.40 / 100 万**

| 項目 | 計算 | 月額（全シナリオ） |
|---|---|---|
| Hosted Zone ×1 | 1 × $0.50 | **$0.50** |
| クエリ（数万–数百万） | 無視できるレベル | **≈ $0.05–0.10** |
| **Route 53 小計** | | **≈ $0.55–0.60** |

> 公式: https://aws.amazon.com/route53/pricing/

---

### 8. Amazon S3

- **構成**: `modules/app-infrastructure/s3.tf`（frontend + images 2 バケット）
- **公式料金**（S3 Standard、東京）:
  - ストレージ: **$0.025/GB-月**
  - PUT/COPY/POST/LIST: **$0.0047 / 1,000 req**
  - GET: **$0.00037 / 1,000 req**
  - DELETE/CANCEL: 無料
  - CloudFront へのオリジンフェッチ: 無料

#### シナリオ別月額（frontend 0.2 GB + images 5 GB）

| 項目 | 低 | 中 | 高 |
|---|---|---|---|
| ストレージ（合計 5.2 GB） | `0.025 × 5.2` = $0.13 | $0.13 | $0.13 |
| リクエスト | ≈ $0.30 | ≈ $0.50 | ≈ $1.50 |
| データ転送（CF 経由） | $0 | $0 | $0 |
| **S3 小計** | **≈ $0.43** | **≈ $0.63** | **≈ $1.63** |

> 公式: https://aws.amazon.com/s3/pricing/

---

### 9. CloudWatch（Logs + Alarms + Container Insights enhanced）

- **構成**: `modules/app-infrastructure/cloudwatch.tf`（Log group ×1 / 30 日保持、Subscription filter ×1、Alarm ×1）+ ECS Container Insights **enhanced**
- **公式料金**（東京）:
  - Logs ingestion: **$0.76/GB**（最初の 5 GB は無料枠）
  - Logs storage（Standard）: **$0.033/GB-月**（最初の 5 GB は無料枠）
  - Alarm: **$0.10/alarm-月**
  - Container Insights **enhanced** for ECS: 1 タスクあたり **約 $0.00638/時間**

#### シナリオ別月額

| 項目 | 低（5 GB / 2 タスク） | 中（30 GB / 3.5 タスク） | 高（100 GB / 7 タスク） |
|---|---|---|---|
| Logs ingestion | 無料枠内: $0 | 25 GB × $0.76 = **$19.00** | 95 GB × $0.76 = **$72.20** |
| Logs storage（30 日） | 無料枠内: $0 | 25 × $0.033 = **$0.83** | 95 × $0.033 = **$3.14** |
| アラーム ×1 | $0.10 | $0.10 | $0.10 |
| Container Insights enhanced | `0.00638 × 2 × 730` = **$9.31** | `0.00638 × 3.5 × 730` = **$16.31** | `0.00638 × 7 × 730` = **$32.61** |
| **CloudWatch 小計** | **≈ $9.41** | **≈ $36.24** | **≈ $108.05** |

> Container Insights `enhanced`（`ecs_web.tf` の `value = "enhanced"`）は通常モードより高額。標準モード（`enabled`）に切り替えると、低シナリオでも月 $9 程度の削減が見込める。詳細は `aws-cost-optimization.md` を参照。
>
> 公式: https://aws.amazon.com/cloudwatch/pricing/

---

### 10. AWS Lambda

- **構成**: `modules/app-infrastructure/lambda.tf`（`kum-notifications-email`、Python 3.11、128 MB、30 秒）
- **公式料金**: 無料枠 100 万 req + 400,000 GB-秒/月。超過時（x86 東京）: $0.20/100 万 req + $0.0000166667/GB-秒
- **月額**: 全シナリオでエラー通知用のため無料枠内 → **$0.00**

- 公式: https://aws.amazon.com/lambda/pricing/

---

### 11. Amazon SQS

- **構成**: `modules/app-infrastructure/sqs.tf`（standard queue ×1）
- **公式料金**: 無料枠 100 万 req/月。超過時（standard 東京）: **$0.40/100 万 req**

| シナリオ | リクエスト数 | 月額 |
|---|---|---|
| 低 | ~0.1 M | $0.00 |
| 中 | ~1 M | $0.00 |
| 高 | ~5 M | 4 × $0.40 = **$1.60** |

- 公式: https://aws.amazon.com/sqs/pricing/

---

### 12. Amazon SNS

- **構成**: `modules/app-infrastructure/sns.tf`（Standard topic ×1、Email subscription ×1）
- **公式料金**: API req $0.50/100 万（最初 100 万無料）、Email $2.00/10 万通
- **月額**: アラーム通知のみ・月数通 → **全シナリオ ≈ $0.00**

- 公式: https://aws.amazon.com/sns/pricing/

---

### 13. Amazon SES

- **構成**: `modules/app-infrastructure/ses.tf`（Domain identity + DKIM + Mail From）
- **公式料金**: **$0.10/1,000 通**（送信）、$0.12/GB（添付）

| シナリオ | 通数 | 月額 |
|---|---|---|
| 低 | 1,000 | **$0.10** |
| 中 | 5,000 | **$0.50** |
| 高 | 20,000 | **$2.00** |

- 公式: https://aws.amazon.com/ses/pricing/

---

### 14. Amazon EventBridge

- **構成**: `modules/app-infrastructure/event_bridge.tf`（Rule ×1、日次 cron → ECS RunTask）
- **公式料金**: AWS サービス発イベントは無料。EventBridge Scheduler 無料枠 14 M invocations/月。
- **月額**: 30 invocations/月 → **全シナリオ $0.00**

- 公式: https://aws.amazon.com/eventbridge/pricing/

---

### 15. SSM Parameter Store

- **構成**: `modules/app-infrastructure/ssm.tf`（Standard parameter ×6 + 既存 SecureString 参照）
- **公式料金**: Standard parameter / API いずれも **無料**
- **月額**: **$0.00**

- 公式: https://aws.amazon.com/systems-manager/pricing/

---

### 16. AWS X-Ray（ADOT Collector 経由）

- **構成**: `ecs_web.tf` の adot-collector サイドカー → X-Ray export
- **公式料金**: 100,000 traces recorded + 1,000,000 retrieved/scanned/月 無料。超過: $5/100 万 recorded
- **月額**: 低・中は無料枠内。高で 200K traces 程度 → **≈ $0.50**

- 公式: https://aws.amazon.com/xray/pricing/

---

### 17. ACM（AWS Certificate Manager）

- **構成**: `modules/app-infrastructure/acm.tf`（frontend cert in us-east-1、backend cert in ap-northeast-1）
- **月額**: パブリック証明書は無料 → **$0.00**

- 公式: https://aws.amazon.com/certificate-manager/pricing/

---

## 月額合計

### シナリオ別総額（FARGATE_SPOT ベース）

| シナリオ | 月額（Spot） | 月額（OnDemand 換算） |
|---|---|---|
| **低**（1–40 RPS） | **≈ $130** | ≈ $170 |
| **中**（40–150 RPS） | **≈ $196** | ≈ $283 |
| **高**（150–300 RPS） | **≈ $590** | ≈ $786 |

### 低トラフィック内訳（Spot ベース）

| サービス | 月額 (USD) | 比率 |
|---|---|---|
| NAT Gateway | $47.12 | 36.3% |
| ALB（IPv4 含む） | $34.16 | 26.3% |
| ECS Fargate Spot | $16.89 | 13.0% |
| RDS | $15.17 | 11.7% |
| CloudWatch（Container Insights enhanced 含む） | $9.41 | 7.2% |
| WAF | $6.60 | 5.1% |
| Route 53 | $0.55 | 0.4% |
| S3 | $0.43 | 0.3% |
| CloudFront | $0.30 | 0.2% |
| SES | $0.10 | 0.1% |
| Lambda / SQS / SNS / EventBridge / SSM / X-Ray / ACM | $0.00 | 0.0% |
| **合計（Spot）** | **≈ $130.73** | 100% |
| 参考: OnDemand 換算合計 | ≈ $170.07 | – |

### 中トラフィック内訳（Spot ベース）

| サービス | 月額 (USD) | 比率 |
|---|---|---|
| ALB（IPv4 含む） | $45.84 | 23.4% |
| ECS Fargate Spot（平均 2.5 task） | $37.13 | 18.9% |
| CloudWatch | $36.24 | 18.5% |
| NAT Gateway | $51.46 | 26.3% |
| RDS | $15.17 | 7.7% |
| WAF | $7.80 | 4.0% |
| CloudFront | $0.90 | 0.5% |
| その他（S3 / Route 53 / SES / SQS 等） | $1.78 | 0.9% |
| **合計（Spot）** | **≈ $196.32** | 100% |
| 参考: OnDemand 換算合計 | ≈ $282.89 | – |

### 高トラフィック内訳（Spot ベース）

| サービス | 月額 (USD) | 比率 |
|---|---|---|
| CloudFront（無料枠超過）| $226.54 | 38.4% |
| CloudWatch | $108.05 | 18.3% |
| ALB（IPv4 + LCU 増） | $86.72 | 14.7% |
| ECS Fargate Spot（6 task） | $84.37 | 14.3% |
| NAT Gateway | $63.86 | 10.8% |
| RDS | $15.17 | 2.6% |
| WAF | $15.00 | 2.5% |
| SES / SQS / X-Ray / S3 等 | $5.73 | 1.0% |
| Route 53 | $0.60 | 0.1% |
| **合計（Spot）** | **≈ $606.04** | 100% |
| 参考: OnDemand 換算合計 | ≈ $786 | – |

### ASCII 内訳ビュー（低トラフィック / Spot）

```
NAT Gateway         ██████████████████████████████████████  $47  (36%)
ALB (+IPv4)         ████████████████████████████            $34  (26%)
ECS Fargate Spot    █████████████                           $17  (13%)
RDS                 ████████████                            $15  (12%)
CloudWatch (enh.)   ███████                                 $ 9  ( 7%)
WAF                 █████                                   $ 7  ( 5%)
その他               ██                                      $ 1  ( 1%)
─────────────────────────────────────────────────────
合計 (Spot)                                                ≈ $131
合計 (OnDemand)                                            ≈ $170
```

---

## 料金に含まれないもの

- **データ転送費**: リージョン間、インターネットアウト（CloudFront 無料枠超過分は反映済み）
- **Terraform state 用 S3 バケット / DynamoDB ロックテーブル**（このモジュール外）
- **ECR リポジトリのイメージストレージ費**: $0.10/GB-月。イメージサイズ × 世代数で変動。
- **GitHub Actions / CI/CD の外部費**
- **日本消費税**（AWS は日本請求先アカウントに別途加算）
- **KMS 利用料**: AWS マネージドキーは無料。CMK の場合 $1.00/key-月 + API 料金。
- **Fargate Spot 中断時の再起動コスト**（タスク再 pull の数秒分、無視できる範囲）

---

## 前回見積もり（2026-04-21 版）との差分

| 項目 | 前回 | 今回 | 差分の根拠 |
|---|---|---|---|
| ECS Fargate 計算ベース | OnDemand のみ | **Spot 主、OnDemand 併記** | コードは `FARGATE_SPOT`。前回は OnDemand 単価で算出していたため過大評価だった |
| ALB 公開 IPv4 | 未計上 | **+ $7.30/月** | 2024-02 以降の課金項目を新規計上 |
| ALB LCU | 1 LCU 固定 | **RPS ベースで変動**（低 1 / 中 3 / 高 10） | RPS スケール反映 |
| NAT Gateway データ処理 | 30 GB 固定 | **シナリオ別**（低 30 / 中 100 / 高 300 GB） | RPS スケール反映 |
| CloudFront | $0.60 固定 | **シナリオ別**、高で $226 | 無料枠超過時のリアル計算（Japan tier の正確な単価適用） |
| CloudWatch Logs | 5 GB 固定 | **シナリオ別**（低 5 / 中 30 / 高 100 GB） | RPS 比例で再見積もり、無料枠 5 GB を反映 |
| Container Insights | 2 task 固定 | **シナリオ別**（低 2 / 中 3.5 / 高 7 task） | 平均 task 数の反映 |
| シナリオ | 単一 | **RPS ベースの低/中/高** | ユーザ要望に応じて分解 |
| 低トラフィック合計 | $167 | **$131（Spot）/ $170（OnDemand）** | Spot 採用 + IPv4 計上 - 若干調整。OnDemand 比較値は前回とほぼ一致 |

> 単価そのものに大きな改定なし。差分の主因は **(1) Spot 単価の反映**、**(2) RPS スケールに連動する LCU/Logs/CF/NAT データ処理の再見積もり**、**(3) Public IPv4 課金の追加**。

---

## 参考リンク（公式料金ページ）

| サービス | URL |
|---|---|
| ECS / Fargate | https://aws.amazon.com/fargate/pricing/ |
| RDS MariaDB | https://aws.amazon.com/rds/mariadb/pricing/ |
| Elastic Load Balancing (ALB) | https://aws.amazon.com/elasticloadbalancing/pricing/ |
| NAT Gateway / VPC | https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html |
| VPC（Public IPv4 含む） | https://aws.amazon.com/vpc/pricing/ |
| CloudFront (Pay-as-you-go) | https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/ |
| AWS WAF | https://aws.amazon.com/waf/pricing/ |
| Route 53 | https://aws.amazon.com/route53/pricing/ |
| Amazon S3 | https://aws.amazon.com/s3/pricing/ |
| CloudWatch | https://aws.amazon.com/cloudwatch/pricing/ |
| AWS Lambda | https://aws.amazon.com/lambda/pricing/ |
| Amazon SQS | https://aws.amazon.com/sqs/pricing/ |
| Amazon SNS | https://aws.amazon.com/sns/pricing/ |
| Amazon SES | https://aws.amazon.com/ses/pricing/ |
| EventBridge | https://aws.amazon.com/eventbridge/pricing/ |
| SSM Parameter Store | https://aws.amazon.com/systems-manager/pricing/ |
| AWS X-Ray | https://aws.amazon.com/xray/pricing/ |
| ACM | https://aws.amazon.com/certificate-manager/pricing/ |
| AWS Pricing Calculator | https://calculator.aws/ |
