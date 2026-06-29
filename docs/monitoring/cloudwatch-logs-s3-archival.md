# CloudWatch Logs の S3 長期アーカイブ設計

ECS（Laravel / Nginx）のログを CloudWatch Logs から S3 に退避し、長期保管する設計のまとめ。
対象は **`terraform/modules/app-infrastructure/`**（stg と将来の prod が共有するモジュール）。preview 環境（`terraform/pr-env/`）は使い捨てのため対象外。

> このドキュメントは「なぜこの設計にしたか」の記録。退避**方式**の決定（Firehose 採用）の詳細な比較は [ADR 0011](../adr/0011-cloudwatch-logs-archive-via-firehose.md) を参照。

---

## 背景・課題

現状、モジュールのロググループ `/ecs/${project_name}` は `retention_in_days = 30` で、**30日経つとログは完全に消え、どこにも残らない**。

- CloudWatch Logs に置き続けるのは高い（**ストレージ ~$0.03/GB/月**。S3 Standard の約1.2倍、Glacier 系の 6〜30倍）。長期保管の置き場としては不適。
- 実務では「直近はすぐ検索できる場所に、それより前は安いストレージに退避して監査・調査に備える」のが定番。
- 本リポは研修目的だが、**stg を本番相当に寄せる**方針のため、stg/prod 共有モジュールにこの仕組みを入れる。

### 目的（退避の動機）

**コンプライアンス/監査対応**を主目的として設計する（「求められたら過去ログを出せる」）。本リポに実際の法令義務はないが、実務の定番である監査用アーカイブの作法に寄せる。

---

## 全体方針：ログを2層で持つ

| 層 | 置き場 | 期間 | 役割 | 検索手段 |
| --- | --- | --- | --- | --- |
| **ホット層** | CloudWatch Logs | 直近 30 日 | 日常の障害調査 | Logs Insights で即検索 |
| **コールド層** | S3（Glacier IR 中心） | 30日〜1年 | 監査・長期保管 | 通常は読まない。必要時に Athena 等 |

- **CloudWatch Logs Insights で検索できるのは CloudWatch に残っている期間だけ**。S3 に落ちたログはすぐには grep できない（Athena 等が必要）。だからホット層＝調査窓、コールド層＝保管庫、と役割を分ける。
- CloudWatch から30日で消えるのと入れ替わるように、S3 側で長期保管する。

```
ECS コンテナ
   │ stdout/stderr (awslogs)
   ▼
CloudWatch Logs  /ecs/${project_name}   ← 30日でホット保持（Insightsで調査）
   │
   ├─ subscription filter (ERROR/CRITICAL)         → Lambda（既存：エラー通知）
   │
   └─ subscription filter (全件・空パターン)        → Firehose → S3（本設計：アーカイブ）
                                                          │
                                                          ▼
                                       S3 バケット（gzip の .gz）
                                          Standard
                                            │ 30日後
                                            ▼
                                          Glacier Instant Retrieval
                                            │ 365日後
                                            ▼
                                          expire（削除）
```

---

## 各決定と理由

### 1. 実装場所：`modules/app-infrastructure/`（stg/prod 共有）

preview（`pr-env`）はPRクローズで丸ごと destroy される使い捨て環境。短命環境のログを長期アーカイブする業務的意味はなく、「destroy 後に S3 だけゴミが残る」運用問題も生む。本番相当の作り込み（30日保持・通知・アラーム）が既にあるモジュール側に退避も足す。

### 2. CloudWatch 保持日数：30日のまま維持

退避を入れても CloudWatch は30日に据え置く。

- コスト最適化だけなら「退避があるなら 7〜14 日に削る」発想もある（CloudWatch ストレージは S3 より高い）。
- だが **Logs Insights で即調査できるのは CloudWatch に残る期間だけ**。直近の障害調査は CloudWatch でやるのが圧倒的に楽。
- stg のログ量は少なく30日でもコストは微小。「調査しやすさ」を「わずかなコスト」より優先。

### 3. 退避方式：subscription filter → Amazon Data Firehose → S3

詳細比較は [ADR 0011](../adr/0011-cloudwatch-logs-archive-via-firehose.md)。要点：

**なぜ Firehose（ストリーミング）を選んだか**

- **目的がコンプライアンス＝「欠損なく全件残す」**。AWS 公式は「継続的にアーカイブする目的での定期エクスポート（`CreateExportTask`）は**非推奨**。その用途には subscription を使え」と明記している。今回はまさにその非推奨ケース。
- 代替の **エクスポートタスク方式（EventBridge + Lambda + `CreateExportTask`）は運用が重い**：
  - **アカウント＋リージョンあたり同時1タスクの制限（緩和不可）** → stg と将来 prod を同じモジュールで回すと競合する。
  - `from`/`to` を自分で渡すため、再実行・時刻ズレで**重複/欠損**が起きやすく、監査ログの完全性を担保しにくい。
  - エクスポート可能まで最大12時間遅延、タスクは24時間でタイムアウト。
- **コスト面で Firehose を避ける理由が薄い**：Firehose は**固定費なし**で取込GB課金のみ。低volumeなら下記のとおり月数十〜数百円。
- 既存の subscription filter（→Lambda エラー通知）と同じ概念の応用で、教材としても自然。

**重要な実装ポイント**

- アーカイブ用の subscription filter は **filter_pattern を空（全件マッチ）** にする。既存のエラー通知フィルタ（ERROR/CRITICAL のみ）と違い、監査目的では**全ログを残す**必要がある。
- ロググループ `/ecs/${project_name}` は web / queue worker / runner / batch の**全コンテナが集約**された単一ロググループ。退避対象はこれ1つでよい。
- subscription filter は **1ロググループあたりデフォルト最大2本**。既存（Lambda）+ 新規（Firehose）= **ちょうど 2/2** で上限内。クォータ緩和申請は不要。
- **Firehose のバッファは大きめ**（例：サイズ 64〜128 MB / 時間 300〜900 秒）に設定する。小さい `.gz` が大量生成されると、後段の S3 ライフサイクル移行で「**128KB未満は移行対象外／128KB分課金**」「移行リクエスト課金が保存節約を食う」罠を踏むため（後述）。

### 4. S3 ストレージクラスとライフサイクル

**ライフサイクル：Standard →（30日後）Glacier Instant Retrieval →（365日後）expire（削除）**

ただし「小さいオブジェクト問題」（後述）への対策として、実装は**2ルールに分ける**：

- **移行ルール**：`object_size_greater_than = 131072`（128KB超）のオブジェクトのみ、30日後に Glacier IR へ移行。128KB未満は移行せず Standard に留める（移行課金の無駄を避ける）。
- **削除ルール**：サイズに関係なく**全オブジェクト**を365日後に expire（削除）。

**なぜ最初の30日は S3 Standard か**

- この期間は CloudWatch にも同じログがホットで残っている（保持30日）。S3 側の直近コピーを無理に冷やす必要はなく、移行リクエスト課金も先送りできる。CloudWatch から落ちるタイミングと S3 の冷却タイミングが揃う。

**なぜ 30日〜1年は Glacier Instant Retrieval（GIR）か**

- 保存 **~$0.004/GB/月**（Standard の約6分の1）と十分安い。
- それでいて **取り出しはミリ秒＝即時**。監査で「8ヶ月前のログを見せて」と言われても、解凍待ちなしで出せる。
- 1年スパン・低volumeではこれが最適点。

**なぜ Deep Archive を使わないか**

- Deep Archive は ~$0.00099/GB とさらに安いが、**取り出しに12〜48時間**、**最低保管180日**の縛りがある。
- 1年・低volume（stg）では Deep Archive の追加節約は**絶対額で数円差**。12〜48時間の取り出し遅延という痛みに見合わない。
- **Deep Archive が正解になるのは「7年保管」級の長期**（→「将来の拡張」参照）。

**なぜ Intelligent-Tiering を使わないか**

- オブジェクト数に応じた監視課金（~$0.0025 / 1,000オブジェクト/月）があり、**小さなログオブジェクトが大量にある用途とは相性が悪い**。アクセスパターンが読めない少数の大きいオブジェクト向け。今回はアクセスパターンが「ほぼ読まない」と明確なので、決め打ちの GIR が安くて素直。

**なぜ 1年で expire するか**

- 一般的なアプリケーションログの保持期限の現実的な落としどころ。明確な法令義務がないため。業種により7年保管が要るケースは「将来の拡張」に記載。

### 5. 小さいオブジェクト問題（コスト上の注意）

S3 ライフサイクルには小オブジェクトの罠がある（実装時に効く）：

- **移行は1オブジェクトごとに課金される**（Glacier 系への移行は ~$0.05 / 1,000オブジェクト）。小さい `.gz` が大量だと、移行リクエスト課金が保存節約を上回りうる。
- **2024年9月以降、128KB未満のオブジェクトはデフォルトで移行されない**。サイズフィルタで強制移行しても、Standard-IA / GIR では128KB分として課金される。
- 対策：**Firehose のバッファを大きめにして、少数の大きい `.gz` にまとめる**（上記4の実装ポイント）＋ **移行ルールに `object_size_greater_than = 131072` を付け、128KB未満は移行せず Standard に留める**（上記4の2ルール構成）。

**低トラフィック環境では小オブジェクトが「常態」になる点に注意**

Firehose は「サイズ（例64MB）に達する」か「時間（例300〜900秒）が経過する」かの**先に来た方**でS3に1オブジェクトを書く。stg のような低トラフィック環境では、64MB が溜まる前に時間バッファが先に発火するため、**毎フラッシュごとに小さな `.gz` が生成される**のが普通（ログがゼロの間は空オブジェクトは作られない）。だから stg では「小さいオブジェクトを Standard に留める」サイズフィルタの効果が大きい。

**ストレージクラスを混在させても検索性・順序は崩れない**

「128KB超は GIR、128KB未満は Standard」と1つのバケット内でクラスが混在するが、これはログ検索や前後関係に影響しない：

- **ストレージクラスは課金の階層であって置き場所ではない**。GIR に移してもS3キー（`app-logs/yyyy/MM/dd/...`）も中身（タイムスタンプ・本文）も変わらない。移動・リネームは起きない。
- **GIR は「即時取り出し（ミリ秒）」クラス**なので、通常の GetObject でそのまま読める（restore 不要）。**Athena は Standard のオブジェクトも GIR のオブジェクトも区別なく1クエリで横断**して読める。混在を意識する必要がない。
- **ログの順序はストレージクラスと無関係**。順序はキーの時刻パーティション（`yyyy/MM/dd/HH`）と各レコードの timestamp フィールドで決まり、検索時に timestamp でソートする（`.gz` 内の時刻順は元々保証されない）。これはクラスが何でも同じ。
- 補足：仮に一部を **Glacier Flexible / Deep Archive（非・即時クラス）** に置いていたら、それらは restore（12〜48時間）しないと Athena が読めずクエリに穴が空く。**GIR に統一したのでこの問題は起きない**（上記「Deep Archive を使わない理由」とも繋がる）。

### 6. 圧縮形式（gzip）

CloudWatch Logs → Firehose → S3 の経路では **gzip 圧縮（`.gz`）** で S3 に着地する。ここは誤解しやすいので仕組みを整理する。

**圧縮しているのは Firehose ではなく CloudWatch Logs 側**

```
CloudWatch Logs ──(gzip 圧縮済みで送る)──▶ Firehose ──▶ S3
```

- CloudWatch Logs は subscription filter で外部（Lambda / Firehose）にログを流すとき、**必ず gzip 圧縮した状態で送る**（設定ではなく CloudWatch の固定挙動）。
- つまり Firehose には**最初から圧縮済みデータが届く**。Firehose が何もしなければそのまま S3 に置くので、**Firehose 側で圧縮設定をしなくても `.gz` で着地する**。
- 保存課金は**圧縮後のバイト数**。テキストログは5〜10倍程度圧縮されるので保存コストはさらに小さい。

**Firehose の「展開（decompression）」は有効化しない**

Firehose には「届いた gzip を解凍してから S3 に置く」オプション（CloudWatch Logs ソース向けの *Decompress source records*）がある。これを**展開（decompression）**と呼ぶ。本設計では**オフにする**。

- **展開オフ（採用）**：gzip のまま S3 へ。容量が小さく保存料が安い。
- **展開オン（不採用）**：非圧縮（平文）で S3 へ着地。さらに **Firehose の取込課金が「解凍後の膨らんだバイト数」基準**になり、テキストログでは取込課金が5〜10倍に増えうる。保存料も増える。
- 展開する意味があるのは、**下流（S3 のログを後で読む側：Athena・人・別のツール）が「非圧縮の平文でないと困る」場合だけ**。実際には `.gz` のまま gunzip すれば読めるし **Athena は `.gz` を直接読める**ので、展開する理由はほぼない。

**S3 に置かれる `.gz` の中身（Athena 利用時の注意）**

展開オフの場合、`.gz` の中身は**生のログ行そのものではなく、CloudWatch が付けたメタ情報（`logGroup` 名・`logStream` 名など）でラップされた JSON** を gzip したもの。Athena で読むときはこの JSON 構造を前提にパースする必要がある（時刻順も保証されないので下流でソート）。

---

## コスト試算（stg / prod）

> **前提**：stg ≈ 100 MB/日（≈ 3 GB/月）、prod ≈ その約10倍 1 GB/日（≈ 30 GB/月）。あくまで概算。実測は CloudWatch メトリクス `IncomingBytes`（ロググループ `/ecs/${project_name}`）で確認できる。
> 単価は東京リージョン目安：Firehose 取込 ~$0.029/GB、S3 Standard ~$0.025/GB/月、Glacier IR ~$0.004/GB/月。為替は ¥150/$ で円換算。

### Firehose（取込課金・固定費なし）

| 環境 | 月間取込 | 月額（×$0.029/GB） | 円換算 |
| --- | --- | --- | --- |
| stg | 約 3 GB | 約 $0.09 | **約 13 円/月** |
| prod | 約 30 GB | 約 $0.87 | **約 130 円/月** |

> 注：Firehose はレコードを5KB単位に切り上げて課金するため、極端に小さいレコードが多いと実額はやや上振れする可能性がある。それでも低volumeでは数十〜数百円規模。

### S3 ストレージ（1年運用の定常状態の目安）

ログは毎月積み上がり、30日で GIR に移って1年で消える。定常状態のおおよその月額：

| 環境 | 定常保管量の目安 | 内訳（Standard + GIR） | 月額 | 円換算 |
| --- | --- | --- | --- | --- |
| stg | 約 36 GB | 3GB×$0.025 + 33GB×$0.004 | 約 $0.21 | **約 30 円/月** |
| prod | 約 360 GB | 30GB×$0.025 + 330GB×$0.004 | 約 $2.1 | **約 320 円/月** |

### 合計（Firehose + S3 ストレージ、リクエスト課金は微小)

| 環境 | おおよその月額合計 |
| --- | --- |
| stg | **約 40〜50 円/月** |
| prod | **約 450〜500 円/月** |

S3 自体の料金はそこまで高くなく、stg のログ量も少ないため、当初の見立てどおり保存コストは小さく収まる。

---

## 実装で必要な Terraform リソース（チェックリスト）

`terraform/modules/app-infrastructure/` に追加する想定。**学習目的のため実コードはここに書かず、必要なリソースと要点のみ列挙**する。

- [ ] **アーカイブ用 S3 バケット**（`aws_s3_bucket`）。`force_destroy` の扱いは要検討（監査ログを誤って消さない方針なら付けない）。
- [ ] **public access block**（`aws_s3_bucket_public_access_block`、全ブロック）。
- [ ] **暗号化**（`aws_s3_bucket_server_side_encryption_configuration`、まずは SSE-S3 / AES256 で十分。厳格なら KMS）。
- [ ] **ライフサイクル**（`aws_s3_bucket_lifecycle_configuration`）：**2ルール構成**。① 移行ルール = `filter { object_size_greater_than = 131072 }` ＋ transition 30日→`GLACIER_IR`（128KB超のみ移行）。② 削除ルール = 全件 expiration 365日。
- [ ] **Firehose 配信ストリーム**（`aws_kinesis_firehose_delivery_stream`、destination = `extended_s3`）。バッファ大きめ（`buffering_size` 64〜128、`buffering_interval` 300〜900）。`prefix` で日付パーティション（例 `app-logs/!{timestamp:yyyy/MM/dd}/`）。
- [ ] **Firehose 用 IAM ロール/ポリシー**（S3 への `PutObject` 等）。
- [ ] **CloudWatch Logs → Firehose の subscription filter**（`aws_cloudwatch_log_subscription_filter`、`filter_pattern = ""` で全件、`role_arn` に CWL が Firehose に流す権限ロール）。
- [ ] **CWL→Firehose 用 IAM ロール**（`logs.amazonaws.com` を信頼、Firehose への `PutRecord*`）。
- [ ] 変数化：保持日数・移行日数・バケット名などを `variables.tf` に出し、stg/prod で差し替え可能に。

---

## 将来の拡張

- **7年など長期保管が必要になったら**：ライフサイクルに `GLACIER_IR →（90日）→ DEEP_ARCHIVE` の段を足し、expiration を伸ばす。取り出し12〜48時間を許容できる前提。
- **改ざん防止（WORM）が必要なら**：S3 Object Lock（コンプライアンスモード）でバケットを作る。監査要件が厳しい場合の選択肢。
- **S3 のログを検索したくなったら**：Athena でテーブルを定義し `.gz` を直接クエリ。Glue でパーティション管理。
- **CloudWatch のコストをさらに削るなら**：ホット保持を14日に短縮（調査窓とのトレードオフ）。

---

## 参考

- AWS: [Exporting log data to S3](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/S3Export.html)（継続アーカイブには非推奨と明記）
- AWS: [Subscription filters → Firehose](https://docs.aws.amazon.com/firehose/latest/dev/writing-with-cloudwatch-logs.html)
- AWS: [S3 Glacier storage classes](https://aws.amazon.com/s3/storage-classes/glacier/)
- AWS: [S3 Lifecycle transition の一般的考慮事項](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-transition-general-considerations.html)（128KB / リクエスト課金）
- 料金: [S3](https://aws.amazon.com/s3/pricing/) / [Data Firehose](https://aws.amazon.com/firehose/pricing/)
</content>
</invoke>
