# CloudWatch メトリクスとアラームの仕組み

CloudWatch のメトリクスがどう識別されるか、ECS / RDS がどのメトリクスをどう送っているか、ログをアラームに使うためになぜメトリクスフィルタが必要か、アラームの評価パラメータが何を決めているか、の解説ドキュメント。

> RDS の監視ツール比較（標準メトリクス / Enhanced Monitoring / Performance Insights）は [rds-observability-tools.md](./rds-observability-tools.md)、RDS 監視の設計判断は [rds-log-monitoring.md](./rds-log-monitoring.md) を参照。このドキュメントは CloudWatch の一般機構を扱う。

---

## メトリクスの一意識別：namespace + metric_name + dimensions の3点セット

CloudWatch のメトリクス（時系列）は、次の3つの組み合わせで一意に識別される。

| 要素 | 役割 | 例 |
| --- | --- | --- |
| `namespace` | メトリクスの属するグループ。AWS サービスは `AWS/RDS` のような固定名、自作メトリクスは任意の名前 | `AWS/RDS` |
| `metric_name` | メトリクスの名前 | `CPUUtilization` |
| `dimensions` | 対象を特定するキーと値の組（0個以上） | `DBInstanceIdentifier = practice-stg-db` |

同じ `AWS/RDS` / `CPUUtilization` でも、dimensions が違えば**完全に別の時系列**として保存される。DB インスタンスが2台あれば `DBInstanceIdentifier` の値だけが違う2本の時系列が並存し、混ざることはない。

アラーム（`aws_cloudwatch_metric_alarm`）はこの3点セットで監視対象を指定する。重要なのは dimensions が**絞り込み検索ではなく完全一致**であること:

- dimensions を正しく指定すれば、その個体の時系列だけを監視する（`cloudwatch.tf` の RDS アラーム4本は `DBInstanceIdentifier` で自分の DB を特定している）
- dimensions を書き忘れる・値を間違えると、「別の対象を監視する」のではなく「**一致する時系列が存在せずデータ無し**」になる。`treat_missing_data = "notBreaching"` の場合、アラームは一度も鳴らないまま沈黙する — 設定ミスに気づきにくい典型パターン
- dimensions が複数ある場合（例: ECS の `ClusterName` + `ServiceName`）は**セット全体**の一致が必要

### 自作メトリクスの分離: namespace 方式と dimensions 方式

自作メトリクス（後述のメトリクスフィルタ産など）では namespace を自分で決められるため、対象の区別に2つの流儀がある。

| 方式 | 例 | 向き |
| --- | --- | --- |
| **namespace で分離** | `practice-stg/RDS` と `practice-prod/RDS` | 環境を完全分離する構成。本リポジトリはこちら（モジュールが `${var.project_name}/RDS` を生成） |
| **dimensions で分離** | namespace は `MyApp/RDS` 固定、`Environment = stg / prod` を dimensions に | 1つのダッシュボードに複数環境を並べる運用。対象が多いとき |

---

## このリポジトリを流れる4系統のメトリクス

| namespace | 供給元 | 有効化 | 料金 | このリポでの用途 |
| --- | --- | --- | --- | --- |
| `AWS/RDS` | RDS が自動送信（1分粒度） | 不要（無効化も不可） | 無料 | RDS メトリクスアラーム4本（CPU / FreeStorageSpace / FreeableMemory / DatabaseConnections） |
| `AWS/ECS` | ECS が自動送信。サービス単位の `CPUUtilization` / `MemoryUtilization`（dimensions: `ClusterName`, `ServiceName`） | 不要 | 無料 | オートスケーリングの `ECSServiceAverageCPUUtilization` / `...MemoryUtilization`（`ecs_web.tf` のターゲット追跡はこの標準メトリクスの事前定義ラッパー） |
| `ECS/ContainerInsights` | Container Insights。タスク数・タスク/コンテナ単位の詳細メトリクス | **オプトイン**（`aws_ecs_cluster` の `setting { containerInsights }`。本リポは `"enhanced"`） | **有料**（カスタムメトリクス扱いの課金。[公式](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cloudwatch-container-insights.html)） | ECS タスク不足アラーム（`RunningTaskCount` / `DesiredTaskCount` の Metric Math） |
| `${project_name}/RDS` | 自作。メトリクスフィルタがログから生成 | メトリクスフィルタの作成 | カスタムメトリクス課金（低頻度なら微小） | RDS エラーログ / スロークエリ急増のアラーム2本 |

ポイント:

- **「標準メトリクス = 無料・自動」と「Container Insights = 有料・オプトイン」は別物**。`AWS/ECS` の CPU/メモリ使用率は Container Insights を切っても送られ続けるが、`RunningTaskCount` のようなタスク数系は Container Insights を有効にしないと存在しない。ECS タスク不足アラームが成立しているのは `containerInsights` を有効化しているから
- RDS 側も同様に、`AWS/RDS` の標準メトリクスは Enhanced Monitoring / Performance Insights と無関係に常時送信される（詳細: [rds-observability-tools.md](./rds-observability-tools.md)）

---

## ログはメトリクスではない：メトリクスフィルタによる数値化

スロークエリログやエラーログは CloudWatch **Logs** に届く**テキスト**であり、メトリクス（数値の時系列）ではない。CloudWatch アラームができるのは「数値と閾値の比較」だけなので、**ログをそのまま監視対象にすることはできない**。

そこで**メトリクスフィルタ**（`aws_cloudwatch_log_metric_filter`）がログとメトリクスの変換点になる:

```
ロググループ（テキストの流れ）
  → pattern（例: "[ERROR]" を含む行）にマッチした件数を数える
  → metric_transformation で指定した namespace / name のメトリクスとして発行（マッチ1件 = 値1）
  → 以降は普通のメトリクスなので、アラームが Sum 等で評価できる
```

本リポジトリの実装（`modules/app-infrastructure/cloudwatch.tf`）:

| フィルタ | pattern | 生成メトリクス | アラーム条件 |
| --- | --- | --- | --- |
| RDS エラーログ | `"[ERROR]"`（`[Warning]` は起動時ノイズのため対象外） | `${project_name}/RDS` / `RdsErrorLogCount` | 5分間の Sum ≥ 1 |
| RDS スロークエリ | `"# Query_time:"`（1エントリが複数行のため、エントリごとに1回だけ出る行を数える） | `${project_name}/RDS` / `RdsSlowQueryCount` | 5分間の Sum ≥ 5 |

注意点:

- メトリクスフィルタは**マッチが発生した瞬間だけ**メトリクスを発行する。マッチ0件の期間は「値0」ではなく「**データ無し**」になるため、アラーム側の `treat_missing_data` の設計（後述）とセットで考える必要がある
- 生成されるのはあくまで「件数」などの数値。**ログ本文はメトリクスに乗らない**ので、通知を受けた後の原因調査はロググループ本体（Logs Insights 等）で行う

---

## アラームの評価パラメータ

`aws_cloudwatch_metric_alarm` の主要パラメータがそれぞれ何を決めているか。すべて本リポジトリのコードに登場する。

| パラメータ | 決めること | 本リポでの使用例 |
| --- | --- | --- |
| `period` | メトリクスを何秒ごとの区間に集計するか | RDS メトリクスアラームは 60、ログ由来は 300 |
| `statistic` | 各区間を1つの数値に潰す方法（Average / Sum / Minimum / Maximum 等） | 件数は `Sum`、使用率は `Average`、FreeStorageSpace のみ `Minimum`（枯渇方向に安全側で評価） |
| `comparison_operator` + `threshold` | その数値と閾値の比較方法 | `GreaterThanThreshold` + 90 など |
| `evaluation_periods` | 直近何区間を見るか（N） | RDS メトリクスアラームは 5 |
| `datapoints_to_alarm` | N 区間中いくつ閾値超過でアラームにするか（M of N） | 5 of 5 =「60秒×5回連続で超過」。一過性のスパイクで鳴らさないための構成。ログ由来は 1 of 1（1区間で即） |
| `treat_missing_data` | データが無い区間の扱い | 全アラームで `notBreaching`（データ無し = 正常）。メトリクスフィルタ産メトリクスはマッチ0件でデータ自体が無いため、これが実質必須 |
| `alarm_actions` / `ok_actions` | 状態遷移時に叩くアクション（SNS 等）。`ok_actions` を入れると復旧も通知される | 両方に SNS トピックを指定 |

`treat_missing_data` の選択肢は4つ: `notBreaching`（正常扱い）/ `breaching`（異常扱い）/ `ignore`（状態維持）/ `missing`（INSUFFICIENT_DATA 状態へ）。「メトリクスが来ない = 対象が死んでいる」を検知したい監視（ハートビート型）では `breaching` を選ぶが、本リポジトリのアラームはすべて「事象が起きたら鳴る」型なので `notBreaching` で統一している。

### period × evaluation_periods は「合計時間が同じ」でも等価ではない

`period=60 × evaluation_periods=5` と `period=300 × evaluation_periods=1` はどちらも「直近5分を見る」が、**判定結果は同じにならない**。CloudWatch は「① `period` ごとの区間を `statistic` で1つの数値に潰す → ②その数値を区間ごとに閾値と比較する」の2段階で動くため、区間の切り方を変えると比較対象の数値そのものが変わる。

**Average の場合**（CPU、閾値 90 超過、1分ごとの値が `100, 100, 100, 100, 60`）:

| 構成 | 判定 | 結果 |
| --- | --- | --- |
| period=60 × 5（5 of 5） | 各1分区間を個別判定 → 超過, 超過, 超過, 超過, 正常 | 5回中4回で**鳴らない** |
| period=300 × 1 | 5分全体の平均 = 92 > 90 | **鳴る** |

長い period + Average は平均化で凸凹が均されて鳴りやすく、短い period × M of M は「毎区間すべて超過」という厳しい条件になる。持続的な負荷だけ拾いたい本リポの RDS メトリクスアラーム4本が 60秒 × 5 of 5 なのはこの意図。

**Sum の場合**（スロークエリが最初の1分に5件、残り4分は0件）:

| 構成 | 判定 | 結果 |
| --- | --- | --- |
| period=300 × 1（Sum ≥ 5） | 5分合計 = 5 | **鳴る**（本リポの実装。「5分間に5件」の意図どおり） |
| period=60 × 5（5 of 5、Sum ≥ 5） | 「毎分5件以上が5分連続」= 合計25件以上が必要 | **鳴らない** |

その他の違い:

- **反応の刻み**: period=60 なら評価窓が1分ごとにスライドし、アラーム化も復旧も1分単位で反応する。period=300 は区間が5分ごとにしか完成しないため、反応も5分刻み
- **M of N の柔軟性**: 「5回中3回超過で鳴らす」のような緩和は evaluation_periods（N）が複数のときだけ成立する。`period=300 × evaluation_periods=1` で使えないのは N=1 だから（period の長さの制限ではない）。`period=300 × evaluation_periods=5 × datapoints_to_alarm=3` = 「直近25分の5分区間のうち3区間で超過」は合法
- **実際にある制約**は2つだけ: `datapoints_to_alarm ≤ evaluation_periods`、および評価窓の合計（period × evaluation_periods）が**最大1日（86,400秒）**

使い分けの整理: **持続性を問うなら短い period × 複数区間**（本リポのメトリクスアラーム）、**期間内の総量を問うなら長い period × 1区間**（本リポのログ由来アラーム）。

---

## メトリクスのライフサイクル：リソースではなくデータ

メトリクスはロググループのような「作成・削除するリソース」ではなく、RDS / ECS / メトリクスフィルタがデータ点を送り込むと受け皿が自動的に現れる「データ」である。**削除 API は存在せず**、Terraform で管理できるのはアラーム（参照する側）とメトリクスフィルタ（生成する仕掛け）だけで、メトリクス本体はどのツールでも管理対象にならない。

### terraform destroy 後の挙動

1. RDS / ECS / メトリクスフィルタが消えると、**新しいデータ点の送信が止まる**
2. 既存のデータ点は**保持期間に従って自動で消えていく**（下表）
3. コンソールのメトリクス一覧には約2週間新データが無いと表示されなくなる（保持期間内のデータは API・グラフからは参照可能）

| データの解像度 | 保持期間 |
| --- | --- |
| 60秒未満（高解像度） | 3時間 |
| 1分 | 15日 |
| 5分（1分データの集約先） | 63日 |
| 1時間 | 455日（約15ヶ月） |

この保持スケジュールは **AWS 側の固定仕様で、ユーザーが変更・延長・短縮する設定は存在しない**（ロググループの `retention_in_days` に相当するものが無い）。15ヶ月を超えて保持したい場合は、CloudWatch Metric Streams 等でメトリクスを S3 などへ書き出して自前保存する。

### ロググループとの違い：後始末が要らない

destroy 後に Terraform 管理外の何かが残る点は「孤児ロググループ」（[rds-log-monitoring.md 決定2](./rds-log-monitoring.md)）と似ているが、性質は正反対:

| | 孤児ロググループ | destroy 後のメトリクス |
| --- | --- | --- |
| 実体 | リソース（永続、保持無期限だと保存課金が続く） | データ（保持期間で自動消滅） |
| 課金 | **保存課金が積み上がり続ける** | 標準メトリクスは元々無料。カスタムメトリクスも課金は「データを送った時間分」の従量制なので、送信が止まれば課金も止まる |
| 対処 | 手動削除 or Terraform 管理化が必要 | **不要**（削除は不可能だが、コストゼロで自然消滅する） |

副次的な利点として、destroy 前の稼働時のメトリクス（例: 前回環境の CPU 推移）は、再 apply 後も保持期間内なら参照できる。

---

## 参考（一次情報）

- [Amazon CloudWatch concepts（namespace / metric / dimension の定義、メトリクスの保持期間）](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html)
- [Using Amazon CloudWatch alarms（評価パラメータ・欠損データの扱い）](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
- [Creating metrics from log events using filters（メトリクスフィルタ）](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/MonitoringLogData.html)
- [Amazon ECS CloudWatch metrics（AWS/ECS 標準メトリクス）](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cloudwatch-metrics.html)
- [Monitor Amazon ECS containers using Container Insights with enhanced observability（有料・オプトインの根拠）](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cloudwatch-container-insights.html)
- [Amazon CloudWatch metrics for Amazon RDS（AWS/RDS 標準メトリクス）](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-metrics.html)
