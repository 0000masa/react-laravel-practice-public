# RDS の可観測性ツール（標準メトリクス / Enhanced Monitoring / Performance Insights）

RDS の監視・分析に使える3つの仕組みの違い・料金・環境別の使い分けをまとめた解説ドキュメント。

> 本リポジトリの RDS 監視の**設計判断**（何を検知し、どう通知するか）は [rds-log-monitoring.md](./rds-log-monitoring.md) と [ADR 0012](../adr/0012-rds-monitoring-detection-analysis-separation.md) に記録している。このドキュメントはその前提となる一般知識を扱い、設計の詳細は繰り返さない。

---

## ログとメトリクスの違い

| | ログ | メトリクス |
| --- | --- | --- |
| 実体 | 出来事1件ごとの記録（テキスト行） | 定期的に記録される数値の時系列 |
| 例 | `[ERROR] InnoDB: Unable to write...`、スロークエリの SQL 本文 | CPUUtilization = 45%（12:00 時点）、FreeStorageSpace = 12GB |
| 得意なこと | 個々の事象の内容・文脈の調査 | 傾向の把握、閾値判定 |
| CloudWatch アラーム | **直接は監視できない** | **監視できる（アラームの対象はメトリクスのみ）** |

CloudWatch アラームができるのは「数値と閾値の比較」だけなので、ログを検知に使うには**メトリクスフィルタで数値に変換する**必要がある（例:「`[ERROR]` を含む行の件数」というメトリクスを作る）。本リポジトリの RDS エラーログ・スロークエリの検知はこの方式（[rds-log-monitoring.md 決定3・4](./rds-log-monitoring.md)）。

---

## 可観測性の3層：測る場所が違うと、見えるものが違う

RDS インスタンスの実体は、AWS の物理サーバー上でハイパーバイザー（1台の物理サーバー上で複数の仮想マシンを動かす仮想化層）が動かしている仮想マシンである。監視データは「どこで測るか」によって3層に分かれる。

| | ① 標準 CloudWatch メトリクス | ② Enhanced Monitoring (EM) | ③ Performance Insights (PI) / Database Insights |
| --- | --- | --- | --- |
| 測る場所 | ハイパーバイザー（VM の**外**） | OS 内のエージェント（VM の**中**） | DB エンジン内のセッションサンプリング |
| 見えるもの | インスタンス全体の合計値（CPU 使用率、空きストレージ、接続数など） | **プロセスごと**の CPU/メモリ、スワップ、ファイルシステム使用率、load average | **SQL ごと**の負荷、待機イベント（ロック待ち/IO 待ち）、DBLoad |
| 答えられる質問 | 「インスタンスは今どのくらい忙しいか」 | 「どのプロセスがリソースを消費しているか」 | 「どの SQL が遅いか、何を待っているか」 |
| 粒度 | 1分（固定） | 1〜60秒（`monitoring_interval` で指定） | 1秒サンプリング |
| データの行き先 | CloudWatch メトリクス（`AWS/RDS` 名前空間） | CloudWatch **Logs**（`RDSOSMetrics` ロググループ） | 専用ダッシュボード（+ 一部メトリクスを CloudWatch に発行） |
| 有効化 | 不要（常時自動） | `monitoring_interval > 0` + 専用 IAM ロール | `performance_insights_enabled = true` |
| 制約 | なし | なし（micro でも使用可） | **db.t2/t3/t4g の micro・small では使用不可**（[ADR 0012](../adr/0012-rds-monitoring-detection-analysis-separation.md)） |

本リポジトリの設計との対応: **検知層**（アラームで気づく）は①と、①へのログの数値化だけで成立する。②③は**分析層**（通知を受けた後に原因を掘る）の道具であり、検知層は②③に依存しない。

---

## よくある誤解：「EM を有効にしないとメトリクスアラームを作れない」

**誤り。** 標準 CloudWatch メトリクスは、EM や PI の設定と無関係に **RDS が自動で・追加料金なしで・1分粒度で**常時発行している（[AWS 公式ブログに明記](https://aws.amazon.com/blogs/database/monitor-real-time-amazon-rds-os-metrics-with-flexible-granularity-using-enhanced-monitoring/)）。無効化する概念自体がない。

標準メトリクスに含まれる主なもの（[公式一覧](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-metrics.html)）:
`CPUUtilization` / `FreeStorageSpace` / `FreeableMemory` / `SwapUsage` / `DatabaseConnections` / `ReadIOPS` / `WriteIOPS` / `ReadLatency` / `WriteLatency` / `NetworkReceiveThroughput` / `BurstBalance` など。

つまり本リポジトリのメトリクスアラーム4本（CPU / FreeStorageSpace / FreeableMemory / DatabaseConnections）は **EM が無効でも完全に機能する**。EM が追加するのは標準メトリクスの拡充ではなく、`RDSOSMetrics` ロググループに送られる **OS 内部の別系統データ**（プロセス一覧など）である。EM を有効にする意味は「アラームの成立」ではなく「**アラームが鳴った後の調査材料**」にある。

---

## 料金

### ① 標準メトリクス — 無料

メトリクスの発行自体に料金はない。課金されるのは CloudWatch 側の利用（アラーム 1本 約 $0.10/月、ダッシュボード、API 大量呼び出し等）のみ。

### ② Enhanced Monitoring — CloudWatch Logs 取り込み課金

EM 自体の機能料金はなく、`RDSOSMetrics` ロググループへの**取り込み量に対する CloudWatch Logs 課金**（東京リージョン 約 $0.76/GB。Logs 無料枠 = 取込 5GB/月）。取込量は粒度で決まる（[公式 FAQ](https://aws.amazon.com/rds/faqs/) の実測値、1インスタンスあたり月間）:

| 粒度 | 取込量/月 | 目安（東京・1インスタンス） |
| --- | --- | --- |
| 60秒 | 0.27GB | **無料枠内でほぼ $0** |
| 30秒 | 0.53GB | 無料枠内 |
| 15秒 | 1.07GB | 無料枠内 |
| 5秒 | 3.21GB | 無料枠付近 |
| 1秒 | 16.07GB | **約 $8〜12/月** |

粒度を細かくするほど・インスタンスが多いほど高くなるため、AWS のガイダンスも「インスタンスごとに粒度を出し分けよ」としている（[Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/amazon-rds-monitoring-alerting/enhanced-monitoring.html)）。

### ③ Performance Insights / Database Insights

- **無料枠: 保持7日 + 100万 API リクエスト/月**（[公式](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.Overview.cost.html)）。多くの用途はこれで足りる
- 有料になるのは保持を 1〜24ヶ月に延長したとき（vCPU 単位の月額）
- **移行に注意**: PI は CloudWatch **Database Insights** に統合され、旧 PI ダッシュボードは **2026年7月31日でサポート終了**。新体系では **Standard = 無料**（旧 PI 無料枠相当）、**Advanced = $0.0125/vCPU 時（約 $9/vCPU/月）**で15ヶ月保持・実行計画キャプチャ等が付く

---

## 実務での stg / prod 設定のベストプラクティス

| | prod | stg |
| --- | --- | --- |
| Enhanced Monitoring | **60秒で有効**が定番（実質無料）。1〜15秒への細粒度化は障害調査時のみ一時的に | 無効 or 60秒。60秒なら実質無料なので有効化しても損はない |
| Performance Insights | **有効（Standard / 無料7日）が定石**。長期分析・規制要件があるときだけ保持延長や Advanced を検討 | 無効か Standard（無料）まで。ただしインスタンスクラスが micro/small なら**そもそも有効化できない** |

補足:

- prod で「EM 60秒 + PI Standard」を両方入れても実質ほぼ無料のため、「問題が起きてから入れる」のではなく「**先に入れておき、問題発生時に即調査できる状態にする**」のが実務の定石（EM/PI は有効化時点からのデータしか持たない。障害が起きた後に有効化しても、その障害のデータは残っていない）
- **Compute Optimizer の RDS ライトサイジング（vCPU 削減）提案は PI が有効でないと出ない**。コスト最適化の観点でも本番 PI 有効化に実益がある（[公式ブログ](https://aws.amazon.com/blogs/database/aws-tools-to-optimize-your-amazon-rds-costs/)）

### 本リポジトリの設定

| | stg（現行） | prod（想定） |
| --- | --- | --- |
| Enhanced Monitoring | **60秒で有効**（`monitoring_interval = 60`。実質 $0、micro でも使用可） | 60秒で有効 |
| Performance Insights | **無効**（db.t4g.micro が非対応のため。選択ではなく制約 — [ADR 0012](../adr/0012-rds-monitoring-detection-analysis-separation.md)） | db.t4g.medium 以上 + 有効（Standard / 無料7日） |

---

## 参考（一次情報）

- [Amazon CloudWatch metrics for Amazon RDS（標準メトリクス一覧）](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-metrics.html)
- [Monitoring OS metrics with Enhanced Monitoring](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Monitoring.OS.html)
- [Amazon RDS FAQs（EM の粒度別取込量）](https://aws.amazon.com/rds/faqs/)
- [Pricing and data retention for Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.Overview.cost.html)
- [Amazon CloudWatch Pricing（Logs 取込・アラーム単価）](https://aws.amazon.com/cloudwatch/pricing/)
- [Enhanced Monitoring（Prescriptive Guidance、粒度の出し分け推奨）](https://docs.aws.amazon.com/prescriptive-guidance/latest/amazon-rds-monitoring-alerting/enhanced-monitoring.html)
- [AWS tools to optimize your Amazon RDS costs（Compute Optimizer と PI の関係）](https://aws.amazon.com/blogs/database/aws-tools-to-optimize-your-amazon-rds-costs/)
- [Monitor real-time Amazon RDS OS metrics with Enhanced Monitoring（標準メトリクスが無料・1分粒度である根拠）](https://aws.amazon.com/blogs/database/monitor-real-time-amazon-rds-os-metrics-with-flexible-granularity-using-enhanced-monitoring/)
