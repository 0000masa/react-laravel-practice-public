# RDS のログと異常検知の設計

RDS（MariaDB）のログの扱いと「異常に気づく仕組み」の設計のまとめ。
対象は **`terraform/modules/app-infrastructure/`**（stg と将来の prod が共有するモジュール）。preview 環境（`terraform/pr-env/`）は独自の RDS を持たず stg の RDS を共有するため（`pr-env/locals.tf` が remote state 経由で `rds_address` を参照）、この設計の対象 RDS は実質1台。

> このドキュメントは「なぜこの設計にしたか」の記録。検知層/分析層の分離と Performance Insights の扱いの判断は [ADR 0012](../adr/0012-rds-monitoring-detection-analysis-separation.md)、用語は [terraform/CONTEXT.md](../../terraform/CONTEXT.md) を参照。標準メトリクス / Enhanced Monitoring / Performance Insights の違い・料金・環境別の使い分けの一般知識は [rds-observability-tools.md](./rds-observability-tools.md) を参照。

---

## 背景・課題（設計前の状態）

- RDS のログは `enabled_cloudwatch_logs_exports = ["error"]` で**エラーログだけ** CloudWatch Logs にエクスポートされていた。ただしそのロググループは RDS が自動作成したもので **Terraform 管理外・保持期間「無期限」**（コストが際限なく積み上がる典型的な落とし穴）。
- **スロークエリログは二重に無効**だった。①エクスポート対象外、②そもそもカスタムパラメータグループが無く MariaDB の `slow_query_log` が OFF（= RDS 内部でもログが生成されていない）。
- エクスポートされたエラーログに**サブスクリプションフィルタ・メトリクスフィルタ・アラームが一切なく、エラーが出ても誰も気づけない**。
- RDS 用の CloudWatch メトリクスアラームなし、RDS Event Subscription なし、Enhanced Monitoring 無効、Performance Insights 無効。

つまり「ログは半分だけ出ているが、気づく仕組みはゼロ」という状態だった。

---

## 全体方針：検知層と分析層を分ける

RDS の監視を役割で2層に分離する（[ADR 0012](../adr/0012-rds-monitoring-detection-analysis-separation.md)）。

| 層 | 役割 | 構成要素 | Performance Insights への依存 |
| --- | --- | --- | --- |
| **検知層** | 異常に「気づく」 | ①ログのメトリクスフィルタ+アラーム ②メトリクスアラーム4本 ③RDS Event Subscription → すべて SNS `rds_alerts`（email）に集約 | **なし**（stg / prod 想定でコードは1文字も変わらない） |
| **分析層** | 通知を受けた**後**に原因を掘る | PI が使える環境（prod 想定）では PI、stg では slowquery ログを Logs Insights で集計 | あり（ここ**だけ**が PI の有無で変わる） |

この分離が効くのは、**PI 自体には通知・アラーム機能が無い**から。AWS 公式（[Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/amazon-rds-monitoring-alerting/publishing-performance-insights-to-cloudwatch.html)）が「PI の中でアラームは作れない。PI のメトリクスで通知したければ CloudWatch アラームにする必要がある」と明記している。**PI の有無が変えるのは「アラートを受け取った後の調査手段の快適さ」だけ**であり、検知層の設計は PI と完全に独立になる。

---

## 前提知識：RDS のログは「生成」と「エクスポート」の2段階

RDS のログが CloudWatch に届くまでには、独立した2つの段階がある。水道に例えると**蛇口（生成）**と**ホース（エクスポート）**。

```
[MariaDB エンジン内部]                  [RDS の機能]                    [CloudWatch Logs]
ログを生成する                   →      ログファイルを転送する      →    ロググループに蓄積
（蛇口: パラメータグループ）            （ホース: enabled_cloudwatch_logs_exports）
```

**第1段階: 生成（蛇口）** — MariaDB 自身が「そのログを書くかどうか・どこに書くか」を決める。ログ種別ごとにルールが違う。

| ログ種別 | 生成のスイッチ | `log_output` の影響 |
| --- | --- | --- |
| エラーログ | **常に ON（切れない）** | **受けない。常にファイルに書かれる** |
| スロークエリログ | `slow_query_log = 1` が必要（デフォルト OFF） | 受ける。`TABLE`（デフォルト）だと DB 内のテーブル `mysql.slow_log` に、`FILE` だとログファイルに書かれる |
| general ログ | `general_log = 1` が必要（デフォルト OFF） | 同上（`mysql.general_log` テーブル or ファイル） |

**第2段階: エクスポート（ホース）** — `enabled_cloudwatch_logs_exports` は「RDS インスタンス内に書かれた**ログファイル**を CloudWatch Logs へ転送する」機能。ここに2つの重要な含意がある。

1. ホースを繋いでいないログ種別は CloudWatch には一切流れない
2. **RDS が CloudWatch に流せるのはファイル出力されたログだけ**。`log_output = TABLE` のままだとスロークエリは `mysql.slow_log` テーブルに書かれるため、エクスポートを有効にしても転送すべきファイルが存在せず、何も流れない。これが本設計でパラメータグループに `log_output = FILE` を設定している理由（エラーログは `log_output` と無関係に常にファイルなので、この設定がなくても転送できる）

補足:

- エクスポートしなくてもログが「無い」わけではない。ログファイルは RDS インスタンス内に存在し、コンソールの「ログとイベント」タブや CLI（`aws rds download-db-log-file-portion`）で閲覧できる。ただし RDS（MariaDB）は組み込みのローテーションを持ち、**ログは1時間ごとに回転・24時間より古いファイルは自動削除**され、合計サイズも**割当ストレージの2%まで**に制約される（ユーザー側で変更不可。[公式](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.MariaDB.LogFileSize.html)）。インスタンス内で見られるのは常に直近1日分だけなので、保存・検索・アラートの土台にするなら CloudWatch へのエクスポートが前提になる
- 蛇口とホースは独立している。例えばエクスポートだけ止めても（ホースを外しても）生成は続くし、CloudWatch 上の既存ログは保持期間が切れるまで残る

### インスタンス内ログの保持はエンジンごとに違う

「インスタンス内のログを自動で整理する」という思想は RDS 全エンジン共通だが（マネージドサービスとして、ログでディスクが埋まり DB が停止するのを自衛している）、ルールと「変更できるかどうか」はエンジンごとに異なる。これは Linux の `logrotate` をユーザーが設定しているのではなく、RDS に組み込まれた仕組みで外せない。

| エンジン | ローテーション | インスタンス内の保持 | ユーザーによる変更 |
| --- | --- | --- | --- |
| **MariaDB**（本リポ） | 1時間ごと | **24時間**より古いファイルは削除。合計は割当ストレージの2%まで | **不可**（[公式](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.MariaDB.LogFileSize.html)） |
| MySQL | 1時間ごと | **2週間**より古いファイルは削除。合計は割当ストレージの2%まで | **不可**（[公式](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.MySQL.LogFileSize.html)） |
| PostgreSQL | ローテーションあり | **デフォルト3日**（`rds.log_retention_period = 4320` 分） | **可能**（1日〜最大7日。[公式](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.Concepts.PostgreSQL.overview.parameter-groups.html)） |

同じ MySQL 系でも MariaDB は24時間・MySQL は2週間と大きく違う。ただしどのエンジンでも上限は高々数日〜2週間で、**「インスタンス内のログは長期保管の場所ではない」という設計は共通**（PostgreSQL のドキュメント自身が CloudWatch Logs への発行を推奨している）。エンジンごとに変わるのは「エクスポートしなかった場合に何日分残るか」という定数だけで、本設計の検知層はどのエンジンでもそのまま通用する。なお、`log_output = TABLE` で DB 内テーブルに書いた場合はこの自動削除の対象外で、**手動でローテーションしない限り増え続ける**（`CALL mysql.rds_rotate_slow_log`）— FILE 出力を選ぶ理由がここにもある。

---

## 各決定と理由

### 1. ログ種別：`error` + `slowquery` を有効化・エクスポート（general / audit は使わない）

RDS for MariaDB で扱えるログは4種類（[公式: Publishing MariaDB logs to CloudWatch Logs](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.MariaDB.PublishtoCloudWatchLogs.html)）。

| ログ種別 | 採否 | 理由 |
| --- | --- | --- |
| `error` | ✅（継続） | 常時有効（無効化不可）。クラッシュ・デッドロック等の一次情報 |
| `slowquery` | ✅（新規） | 性能劣化の検知・調査の要。実務の最低ラインは error + slowquery |
| `general` | ❌ | 全 SQL を記録するため量・取り込みコストが膨大。実務でも常時 OFF、障害調査時に一時的に ON が定番 |
| `audit` | ❌ | MARIADB_AUDIT_PLUGIN（オプショングループ）が別途必要。監査要件がある場合の機能で本リポには過剰 |

`slowquery` の有効化には**カスタムパラメータグループ**（`aws_db_parameter_group`）が必要:

- `slow_query_log = 1` … スロークエリログの生成を有効化
- `long_query_time = 1` … 閾値1秒。MariaDB デフォルトは10秒だが、Web アプリで10秒は既に大事故。**1〜2秒に締めるのが実務の定石**（AWS 公式の設定例も 1.0 秒）
- `log_output = FILE` … **CloudWatch へのエクスポートは FILE 出力が前提**。RDS for MySQL/MariaDB のデフォルトは TABLE なので明示的な変更が必要（仕組みは上の「前提知識」セクション参照）
- `log_queries_not_using_indexes` は **OFF のまま**（小さいテーブルへの正常なクエリもノイズとして拾うため）

### 2. ロググループは Terraform 管理・保持30日

**RDS が自動作成するロググループは保持期間「無期限」**になる。ベストプラクティスは「`aws_cloudwatch_log_group` を retention 付きで **RDS より先に** Terraform で作る」。命名は RDS の規則 `/aws/rds/instance/<identifier>/<log-type>` に正確に一致させれば RDS はそれを使う。

- 保持期間は **30日**。既存の ECS ロググループ（`cloudwatch.tf` の `retention_in_days = 30`）と揃え、監査要件のない学習環境でのコストと調査可能期間のバランス点とする

本リポは常時稼働ではなく**都度 `terraform destroy` する運用**のため、既存環境との衝突より「destroy ↔ apply のサイクルで孤児を作らない」ことが論点になる:

- **孤児ロググループの一次対処**: RDS が自動作成したロググループは Terraform 管理外なので **`terraform destroy` では消えない**。実際に過去の稼働分の `/aws/rds/instance/<identifier>/error` が無期限保持のまま残存していた。中身は破棄済みインスタンスのログで価値がないため、**apply 前に手動削除**する（`aws logs delete-log-group`）。残したまま apply すると `ResourceAlreadyExistsException` で失敗する（残す価値がある場合のみ `terraform import`）
- **孤児の再発防止**: ロググループを Terraform 管理にすれば以後は destroy で一緒に消える。ただし破棄順序が「ロググループ → RDS」だと、**RDS が削除処理中の最終ログ書き込みでロググループを再作成**して孤児が復活することがある。`aws_db_instance` に `depends_on` でロググループを指定し、依存の逆順で破棄される性質を使って「RDS 削除 → ロググループ削除」の順序を保証する（これは作成時の「ロググループを RDS のログ有効化より先に作る」順序も同時に満たす）。それでも稀に孤児が再発したら、次回 apply 前に手動削除する

### 3. エラーログの通知：メトリクスフィルタ + アラーム + SNS（Lambda は使わない）

「特定のログが出たら通知」の実務パターンは2つ。

| 方式 | 仕組み | 向くケース |
| --- | --- | --- |
| **(a) メトリクスフィルタ + アラーム + SNS** | パターン一致回数をメトリクス化→閾値超過でアラーム | 件数・頻度ベースの単純な通知。Lambda 不要。**CIS / Security Hub の推奨実装もこれ** |
| (b) サブスクリプションフィルタ + Lambda | ログをリアルタイムで Lambda にストリームし任意処理 | 1件ごと即時・Slack 整形など**通知内容の加工**が要る場合 |

本リポは両方の実装例を既に持つ（(a) = ECS タスク不足アラーム、(b) = Laravel `staging.ERROR/CRITICAL` → Lambda → SES）が、RDS エラーログには **(a) を採用**:

- 単純な「エラーが出たら知りたい」は (a) が実務の第一選択。Lambda という運用対象を増やさない
- 既存 Lambda（`notification_function`）のパースロジックは **Laravel の JSON ログ形式前提**。MariaDB のエラーログはプレーンテキストなので、流用すると Lambda に形式分岐が増えて複雑化する
- フィルタパターンは MariaDB の深刻度タグ `[ERROR]` にマッチ。`[Warning]` は起動時等にも出るノイズなので対象外
- 閾値は「**5分間に1件以上**」

通知先の SNS トピック `rds_alerts`（email 購読）を新設し、検知層の3系統（ログ・メトリクス・イベント）をすべてここに集約する。

### 4. スロークエリ：1件ごとに通知しない（件数閾値アラームのみ）

**スロークエリの1件ごと通知はアンチパターン**。正常時でも一定量発生するためアラート疲れを起こす。実務のスタンスは:

1. 通常は **Performance Insights / Database Insights で定期レビュー**（AWS の一次推奨）
2. 通知するなら**件数の閾値**で「異常な急増」だけ拾う
3. ログ自体は定期集計・レビューへ

本リポでは stg のインスタンスクラス（db.t4g.micro）が PI 非対応（後述）のため、**メトリクスフィルタで件数をカウントし「5分間に5件以上」でアラーム**する方式を採る。`long_query_time = 1秒` との組み合わせで「1秒超えのクエリが5分で5回 = 明らかな異常」の水準。閾値は運用しながらベースラインに合わせて調整する（最初から完璧な閾値は誰にも分からない、が実務の作法）。

### 5. Performance Insights との関係：stg は無効「しかできない」、prod 想定では有効

`stg/terraform.tfvars` の `performance_insights_enabled = false` は当初「stg に細かい監視は不要」という判断として記憶されていたが、実際には **PI は db.t2 / t3 / t4g の micro・small 非対応**（[公式: Database Insights のインスタンスクラス対応表](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_DatabaseInsights.Engines.html)）であり、db.t4g.micro では true にすると apply が `InvalidParameterCombination` で失敗する。**false は選択ではなく制約**。

- stg: micro のまま `false` 継続。スロークエリの深掘りは Logs Insights での集計で代替
- prod 想定: `db.t4g.medium` 以上 + `performance_insights_enabled = true`（7日保持は無料）。PI を有効にすると `DBLoad` / `DBLoadCPU` / `DBLoadNonCPU` が CloudWatch に自動発行されるため、`DBLoad` アラームを検知層に**追加**できる（追加であって、既存検知層の変更ではない）
- インスタンスクラスを medium に上げて stg でも PI を使う案は、料金約4倍のため却下（詳細は [ADR 0012](../adr/0012-rds-monitoring-detection-analysis-separation.md)）

### 6. メトリクスアラーム：定番4本（公式推奨閾値ベース、閾値は tfvars 変数）

AWS 公式の[推奨アラーム集（Best Practice Recommended Alarms）](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Best_Practice_Recommended_Alarms_AWS_Services.html)の RDS セクションに基づく。

| メトリクス | 公式推奨 | stg（db.t4g.micro / RAM 1GB / 20GB）での具体値 | 検知したいもの |
| --- | --- | --- | --- |
| `CPUUtilization` | > 90% | 90% | バーストクレジット枯渇・暴走クエリ |
| `FreeStorageSpace` | < 割当の10% | < 2GB | ディスク枯渇 → DB 停止の予防 |
| `FreeableMemory` | < 総メモリの25% | < 256MB | スワップ・OOM の予兆 |
| `DatabaseConnections` | > max_connections の90% | > 72 前後 | 接続リーク・プール枯渇 |

注意: `max_connections` は固定値ではなく、MariaDB では `{DBInstanceClassMemory/12582880}` という**メモリ連動の式**で決まる（t4g.micro で約80）。閾値をハードコードするとインスタンスクラス変更時にずれるため、**閾値は `rds_config` 等の tfvars 変数として環境ごとに渡す**（prod 想定との整合）。`alarm_actions` に加えて `ok_actions` にも `rds_alerts` を入れ、復旧も通知する（既存 ECS アラームと同じ流儀）。

### 7. RDS Event Subscription：6カテゴリ購読

ログにもメトリクスにも出ない「RDS 自体のライフサイクルイベント」を拾う層。`aws_db_event_subscription`（`source_type = db-instance`）で以下を購読し、`rds_alerts` へ流す。

| カテゴリ | 拾うもの |
| --- | --- |
| `failure` | インスタンス障害 |
| `failover` | Multi-AZ フェイルオーバー発生 |
| `low storage` | ストレージ残量逼迫 |
| `availability` | 停止・再起動 |
| `maintenance` | メンテナンスウィンドウでの再起動等（月曜 0:00 JST に「なぜ止まった？」と慌てないため） |
| `configuration change` | DB 設定変更（「誰かが勝手に変えた」の検知。ガバナンス用途） |

`configuration change` は `apply_immediately = true` で頻繁に apply する本リポでは**自分の apply のたびに通知が来る**が、通知先が自分だけなので許容し、prod 想定と同じ構成を維持する判断とした。参考: Control Tower / Config ルールの推奨は `failure`・`maintenance`・`configuration change`、DBA（データベース管理者）の現場定番が `failover`・`low storage`・`availability`。本設計はその和集合。

---

## コストの考え方

- **RDS のログエクスポート自体は無料**。かかるのは CloudWatch Logs の取り込み（Vended Logs 標準で $0.50/GB〜、[料金](https://aws.amazon.com/cloudwatch/pricing/)）と保存
- 保存コストの最大の対策が **retention 設定**（本設計の30日）。無期限放置が最も高くつく
- `general` ログを常時 ON にしない・`long_query_time` を下げすぎないことも取り込み量の抑制になる
- SNS（email）・メトリクスフィルタは実質無料圏。アラームは1本 $0.10/月程度

---

## この設計で作る Terraform リソース（実装時のチェックリスト)

- `aws_db_parameter_group`（mariadb11.4 ファミリー: `slow_query_log` / `long_query_time` / `log_output`）+ `rds.tf` の `parameter_group_name` 参照
- 事前作業: 残存している孤児ロググループ `/aws/rds/instance/<identifier>/error` を手動削除（`aws logs delete-log-group`）
- `aws_cloudwatch_log_group` ×2（error / slowquery、retention 30日）+ `aws_db_instance` に `depends_on` で両ロググループを指定（destroy 順序の保証）
- `stg/terraform.tfvars`: `enabled_cloudwatch_logs_exports = ["error", "slowquery"]` に変更、PI 非対応制約のコメント追記
- `aws_sns_topic` `rds_alerts` + email 購読
- `aws_cloudwatch_log_metric_filter` ×2 + `aws_cloudwatch_metric_alarm` ×2（エラーログ `[ERROR]` 1件/5分、slowquery 5件/5分）
- `aws_cloudwatch_metric_alarm` ×4（CPU / FreeStorageSpace / FreeableMemory / DatabaseConnections、閾値は tfvars 変数）
- `aws_db_event_subscription`（6カテゴリ → `rds_alerts`）

---

## 参考（一次情報）

- [Publishing MariaDB logs to Amazon CloudWatch Logs](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.MariaDB.PublishtoCloudWatchLogs.html)
- [Amazon RDS DB engine, Region, and instance class support for Database Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_DatabaseInsights.Engines.html)（PI の micro/small 非対応）
- [Publishing Performance Insights metrics to CloudWatch（Prescriptive Guidance）](https://docs.aws.amazon.com/prescriptive-guidance/latest/amazon-rds-monitoring-alerting/publishing-performance-insights-to-cloudwatch.html)（PI 内でアラーム不可の明記）
- [Best practice alarm recommendations for AWS services（RDS セクション）](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Best_Practice_Recommended_Alarms_AWS_Services.html)
- [Set alarms on Performance Insights metrics using Amazon CloudWatch（AWS Database Blog）](https://aws.amazon.com/blogs/database/set-alarms-on-performance-insights-metrics-using-amazon-cloudwatch/)
- [Amazon CloudWatch Pricing](https://aws.amazon.com/cloudwatch/pricing/)
