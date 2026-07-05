---
status: accepted
---

# RDS 監視は「検知層」と「分析層」に分離し、検知層は Performance Insights に依存させない

## 背景

stg の RDS（`db.t4g.micro`、MariaDB 11.4）は `performance_insights_enabled = false` になっている。当初は「stg に細かい監視は不要」という判断として記憶されていたが、実際には **Performance Insights（PI）は db.t2 / t3 / t4g の micro・small をサポートしない**（[公式: Database Insights のエンジン・インスタンスクラス対応表](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_DatabaseInsights.Engines.html)）。つまり true にしても apply が `InvalidParameterCombination` で失敗する。**false は選択ではなく制約**であり、これはコードから読み取れない。

一方で「PI の有無によって、通知するログやアラームの設定が変わる構成にはしたくない」という要求がある。公式ドキュメントは「**PI の中でアラームは作れない。PI のメトリクスで通知したければ CloudWatch アラームにする必要がある**」と明記している（[Prescriptive Guidance: Publishing Performance Insights metrics to CloudWatch](https://docs.aws.amazon.com/prescriptive-guidance/latest/amazon-rds-monitoring-alerting/publishing-performance-insights-to-cloudwatch.html)）。つまり PI は通知の主体になれない。

## 決定

RDS の監視を役割で2層に分離する。

- **検知層**（異常に「気づく」仕組み）: RDS ログ（error / slowquery）のメトリクスフィルタ + CloudWatch メトリクスアラーム + RDS Event Subscription → SNS `rds_alerts`（email 購読）。**PI に一切依存しない。** stg と prod 想定とで Terraform コードは1文字も変わらない。
- **分析層**（通知を受けた**後**に原因を掘る手段）: PI が使える環境（prod 想定: `db.t4g.medium` 以上）では PI、使えない stg では slowquery ログを CloudWatch Logs Insights で集計する。**PI の有無が変えるのは「アラートを受け取った後の調査手段の快適さ」だけ。**

stg は `db.t4g.micro` のまま `performance_insights_enabled = false` を**継続**する（制約上 true 不可）。prod 想定では PI を有効化し、必要なら `DBLoad` アラームを検知層に**追加**する — これは追加であって既存検知層の変更ではない。

## 考慮した代替案

- **stg のインスタンスクラスを `db.t4g.medium`（PI サポート最小クラス）に上げて PI を有効化する**。却下理由: 料金が micro の約4倍になり、学習用の常設環境には過大。検知層が PI 非依存である以上、stg で PI が無くても「気づく」能力は落ちない。

## トレードオフ / 影響

- stg でのスロークエリの深掘りは PI より不便（Logs Insights でのログ集計）。代わりに件数閾値アラーム（急増検知)で「気づき」を担保する。
- 環境差分（PI の有効/無効）は tfvars の値の違いとして意図的に管理し、micro/small 非対応の制約は `terraform.tfvars` の該当行コメントにも残す。
