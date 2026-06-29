---
status: accepted
---

# CloudWatch Logs の S3 長期アーカイブは Firehose ストリーミングで行う（エクスポートタスクは使わない）

## 背景

モジュール（`terraform/modules/app-infrastructure/`、stg/prod 共有）のロググループ `/ecs/${project_name}` は `retention_in_days = 30` で、30日経つとログが完全に消える。**コンプライアンス/監査を意識して、消える前に S3 へ退避して長期保管**したい（全体設計は [docs/monitoring/cloudwatch-logs-s3-archival.md](../monitoring/cloudwatch-logs-s3-archival.md)）。

CloudWatch Logs を S3 に出す方式には大きく2系統あり、どちらを採るかでインフラ構成・コスト・運用の重さが変わる。

- **(a) エクスポートタスク方式**：EventBridge（スケジュール）→ Lambda → `CreateExportTask` で定期的に S3 へ一括書き出し（バッチ）。
- **(b) Firehose ストリーミング方式**：ロググループに subscription filter を足し、Amazon Data Firehose 経由で S3 へ準リアルタイム配信。

当初は「研修として EventBridge+Lambda を書く題材になる」「Firehose は常時課金で高そう」という理由で (a) も有力に見えていた。

## 決定

**(b) subscription filter → Amazon Data Firehose → S3 を採用する。**

- アーカイブ用 subscription filter は **`filter_pattern = ""`（全件）** とし、全ログを残す（既存のエラー通知フィルタは ERROR/CRITICAL のみで別物）。
- subscription filter は1ロググループあたりデフォルト最大2本。既存（Lambda）+ 新規（Firehose）= **2/2** で上限内、クォータ緩和申請は不要。
- Firehose のバッファは大きめ（サイズ 64〜128MB / 時間 300〜900秒）にし、少数の大きい `.gz` にまとめる。

## 考慮した代替案

- **(a) エクスポートタスク方式（EventBridge + Lambda + `CreateExportTask`）**。Firehose 不要で取込課金もなく、低volumeなら最安。EventBridge+Lambda のオーケストレーションは学習題材にもなる。**却下理由**：
  - AWS 公式が「**継続的にアーカイブする目的での定期エクスポートは非推奨。その用途には subscription を使え**」と明記しており、今回の目的（継続的な監査アーカイブ）はまさにこの非推奨ケース。
  - **アカウント＋リージョンあたり同時1エクスポートタスクの制限（緩和不可）**。stg と将来 prod を同じモジュールで回すと競合し、直列化やポーリングの作り込みが要る。
  - `from`/`to` を自分で渡すため、再実行・時刻ズレで**重複/欠損**が起きやすく、監査ログの完全性を担保しにくい。
  - エクスポート可能まで最大12時間遅延、タスクは24時間でタイムアウト。
- **(c) CloudWatch に長期保持（退避しない）**。プラミング不要。**却下理由**：CloudWatch ストレージは ~$0.03/GB/月で S3 の 6〜30倍。1年以上の保管では高すぎる。

## トレードオフ / 影響

- **Firehose という常時稼働基盤が増える**（配信ストリーム + IAM ロール2種）。ただし**固定費はなく取込GB課金のみ**で、想定volumeでは stg 約13円/月・prod 約130円/月（[設計ドキュメント](../monitoring/cloudwatch-logs-s3-archival.md)の試算）。
- 「研修として Lambda オーケストレーションを書く経験」は得られない。代わりに subscription filter / Firehose / S3 ライフサイクルの組み立てを学ぶ。
- subscription filter が **2/2 の上限**に達する。今後このロググループに3本目（別の流し先）が欲しくなったら、クォータ緩和申請か Firehose 側での分岐が必要になる。
- Firehose の「展開」は有効化しない（展開後GB課金を避け、gzip のまま安く保存する）。
</content>
