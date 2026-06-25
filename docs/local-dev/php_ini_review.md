# `environment/ecr/php.ini` レビュー (ECS 1 タスク 2 コンテナ構成の観点)

## レビュー対象

- `environment/ecr/php.ini` (全 61 行)
- 適用先: `docker/ecr/backend/Dockerfile` で `/usr/local/etc/php/conf.d/custom.ini` に COPY (L45)
- ベース: `php:8.2-fpm-bullseye`

## 前提とする運用構成

| 項目 | 値 |
| --- | --- |
| 起動タイプ | AWS ECS Fargate |
| タスク内コンテナ | `nginx-container` + `backend-container` (PHP-FPM) の 2 つ |
| ネットワークモード | `awsvpc` (同一 network namespace、`127.0.0.1:9000` で IPC) |
| ログドライバ | `awslogs` (stdout / stderr を CloudWatch Logs に流す) |
| 外部入口 | ALB → nginx:80 → PHP-FPM:9000 |
| セッションストア | `SESSION_DRIVER=database` (ECS タスク跨ぎで保持される) |

## 総合評価

**総評: 初回レビューで発見された実害項目はすべて修正適用済み。残タスクはインフラ側の確認のみ。**

初回レビュー時点では以下 3 点に問題がありましたが、本ドキュメント内の修正提案に沿ってコード側の対応は完了しています。

| # | 内容 | 初回の深刻度 | 現状 |
| --- | --- | --- | --- |
| 1 | `upload_max_filesize = 20M` と nginx の `client_max_body_size` 未設定 (デフォルト 1M) が不整合 | 高 | ✅ 修正済み (dev / prod 両方の nginx.conf に `client_max_body_size 20m;` を追加) |
| 2 | `date.timezone = "Asia/Tokyo"` が Laravel `config/app.php` の `timezone = 'UTC'` と不一致 | 中 | ✅ 修正済み (php.ini 側を `"UTC"` に変更、Laravel 側は元々 UTC なので揃った) |
| 3 | コメントに「OpCache (JITコンパイル) 設定」とあるが、JIT 関連設定は未導入 | 低 | ✅ 修正済み (JIT は使わない方針のためコメントから削除し、意図を明記) |
| 4 | ALB / nginx / PHP のタイムアウトが全レイヤ 60s で境界事故リスク | 中 | ✅ コード側は nginx に `fastcgi_read_timeout 70s;` 追加済み / **インフラ側: ALB idle timeout を 75s に上げる作業が未実施 (AWS コンソールまたは Terraform / CDK で対応)** |
| 5 | `pm.max_children = 10` × `memory_limit = 256M` = 最大 2.5GB のメモリ要件確認 | 中 | ⚠️ **未確認** (Fargate タスクメモリ ≥ 3GB 割当になっているかの確認が必要) |

以降、セクションごとの詳細レビューと修正内容の記録を記載します。

---

## 各設定項目のレビュー

### 1. リソース制限

```ini
memory_limit = 256M
post_max_size = 20M
upload_max_filesize = 20M
max_execution_time = 60
```

| 設定 | 評価 | コメント |
| --- | --- | --- |
| `memory_limit = 256M` | ○ | 画像処理 / バッチを考えると妥当。ただし `pm.max_children = 10` (`zz-custom.conf`) との掛け算で **最大 2.5GB** 必要。Fargate タスクのメモリ割当が 1GB 以下なら OOM リスクあり。タスク定義のメモリが 2GB 以上であることを確認する必要あり (**未確認**) |
| `post_max_size = 20M` | ◎ | ✅ nginx `client_max_body_size 20m;` と揃った |
| `upload_max_filesize = 20M` | ◎ | 同上 |
| `max_execution_time = 60` | ○ | ✅ nginx `fastcgi_read_timeout 70s;` を追加済み。**インフラ側の ALB idle timeout のみ未対応 (75s 推奨)** |

### 2. エラーログ設定

```ini
display_errors = Off
display_startup_errors = Off
log_errors = On
error_log = /dev/stderr
```

| 設定 | 評価 | コメント |
| --- | --- | --- |
| `display_errors = Off` | ◎ | 本番で必須 |
| `display_startup_errors = Off` | ◎ | 同上 |
| `log_errors = On` | ◎ | CloudWatch 送出に必須 |
| `error_log = /dev/stderr` | ◎ | **awslogs ドライバ連携に必須**。コンテナの stderr → CloudWatch Logs の経路が成立する。**1 タスク 2 コンテナ構成でもコンテナごとに awslogs が設定されるため、backend-container の stderr がそのまま `/aws/ecs/<task>/backend-container` 相当のロググループに流れる**。この設定が `/var/log/php/error.log` 等のファイルになっていると、Fargate のエフェメラルストレージに書き込まれて誰にも見られない。OK |

→ **ECS 2 コンテナ構成に対して正しく設定されています**。

### 3. セキュリティ

```ini
expose_php = Off
```

- ◎ `X-Powered-By: PHP/x.y.z` ヘッダを抑止。妥当。
- 補足: nginx 側も `server_tokens off;` が `environment/ecr/nginx.conf` L6 に入っている。2 コンテナ両方でバージョン秘匿ができている整合性 OK。

### 4. 文字コード / 日本語設定

```ini
default_charset = "UTF-8"
mbstring.language = Japanese
mbstring.internal_encoding = UTF-8

[Date]
date.timezone = "UTC"
```

| 設定 | 評価 | コメント |
| --- | --- | --- |
| `default_charset = "UTF-8"` | ◎ | 妥当 |
| `mbstring.language = Japanese` | ◎ | 日本語プロジェクトで妥当 |
| `mbstring.internal_encoding = UTF-8` | ◎ | 妥当 |
| `date.timezone = "UTC"` | ◎ | ✅ Laravel `config/app.php` の `'timezone' => 'UTC'` と揃え、PHP ランタイム全域で UTC 統一 |

#### UTC 統一の運用メモ

- CloudWatch Logs / DB の `created_at` など、システム側のタイムスタンプはすべて UTC で保存される。
- 日本語での表示 (画面 / PDF / メール本文など) が必要な箇所は、**ビュー層で `Carbon` を使って JST に変換する** 方針:

```php
// 例: Blade テンプレート
{{ $order->created_at->setTimezone('Asia/Tokyo')->format('Y-m-d H:i') }}

// 例: メール本文生成
$jst = $createdAt->copy()->setTimezone('Asia/Tokyo');
```

- アプリケーション全体を将来的に JST にしたい場合は `config/app.php` の `'timezone'` と `php.ini` の `date.timezone` の両方を `'Asia/Tokyo'` に揃える。どちらを真実の源泉にしても構わないが、**2 箇所で別の値を持たないこと** が原則。

### 5. OpCache

```ini
[opcache]
opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = 10000
opcache.validate_timestamps = 0
```

#### OpCache とは

PHP はスクリプト言語なので、リクエストのたびに `.php` ファイルを読み込み → 構文解析 → バイトコードに変換 → 実行、という処理を行います。**OpCache** はこの「バイトコードに変換した結果」をメモリに保持し、次回以降のリクエストで解析をスキップする仕組みです。本番では **有効化しないと明確に遅い** ので、ほぼ必須の設定です。

```
[OpCache 無効の場合]   リクエスト → ファイル読込 → 解析 → バイトコード化 → 実行
[OpCache 有効の場合]   リクエスト → (キャッシュヒット) → 実行
```

#### 各設定の解説

**`opcache.enable = 1`**
- OpCache 機能そのもののオン/オフスイッチ。`1` で有効、`0` で無効。
- 本番では必ず `1`。逆に `0` にするとキャッシュが効かず、毎回フルコンパイルするので明確に遅い。
- 評価: ◎

**`opcache.memory_consumption = 128`** (単位: MB)
- OpCache が使ってよいメモリの上限サイズ。キャッシュしたバイトコードはここに貯めこまれる。
- **不足するとどうなるか**: メモリが埋まると古いキャッシュから順に追い出され (または完全に破棄されて) フルコンパイルが再発生するため、**足りないと逆に遅くなる**。Laravel 規模なら 128MB はほぼ十分だが、本番で `opcache_get_status()` を叩いて `free_memory` が常に 0 付近なら増やす。
- 評価: ○ (現値 128 で Laravel としては妥当)

**`opcache.interned_strings_buffer = 8`** (単位: MB)
- 「**interned strings (インターン化された文字列)**」を格納するバッファ。
- interned strings とは、PHP 内部で **同じ内容の短い文字列 (クラス名 / 関数名 / プロパティ名など) を 1 つにまとめてメモリを節約する仕組み**。例: `"User"` という文字列が 1000 箇所で使われていても、メモリ上の実体は 1 個だけ持つ。
- この領域が不足すると文字列の重複除去ができなくなり、メモリと CPU を無駄に使う。
- Laravel のような巨大フレームワークではクラス名が多いため、`8MB` だと少し手狭。`16` に上げるのも一案。
- 評価: ○ (動くが、最適化余地あり)

**`opcache.max_accelerated_files = 10000`**
- OpCache が **何個のファイルをキャッシュできるか** の上限。
- PHP のデフォルトは `2000`。Laravel はフレームワーク + アプリのファイル数で簡単に数千を超えるので、デフォルトだとキャッシュに乗り切らないファイルが出てくる。
- `10000` なら Laravel + ベンダーライブラリを十分カバー。
- 実測値は `opcache_get_status()` の `num_cached_scripts` で確認できる。
- 評価: ◎

**`opcache.validate_timestamps = 0`** (本設定の中で最も重要)
- **「OpCache はキャッシュしているファイルが更新されたかチェックするべきか」** のスイッチ。
- `1` (デフォルト) = 毎リクエストごとに `stat(2)` システムコールでファイルの更新時刻を確認し、変わっていたら再コンパイルする。ファイルを編集したら即反映される。
- `0` = 一切チェックしない。一度キャッシュしたら永遠にそのバージョンを使い続ける。
- **本プロジェクトでは `0` が正解** な理由:
  - ECS コンテナのイメージは **ビルド時点で固まっており、実行中に中身が変わらない** (イミュータブル)。
  - 従って更新チェックは常に「変わっていない」という結論になる **無駄な処理**。
  - `stat(2)` はディスク I/O が発生するため、毎リクエストの積み重ねで無視できない負荷になる。
  - 0 にすることでこの無駄な I/O を削減 → 高速化。
- デプロイで新しいコードを反映するときは、**新イメージで新しいコンテナを起動する** (= OpCache はゼロから新コードでウォームアップされる) ので、古いバージョンを掴み続ける心配はない。
- 開発環境 (docker-compose) でコードを書き換えてすぐ反映させたい場合は、php.ini 側で `1` にする必要がある (ただし現プロジェクトでは dev 側に php.ini を置いていないのでベースイメージのデフォルトが効く)。
- 評価: ◎

#### JIT (実行時機械語変換) について — 本プロジェクトでは使わない方針

PHP 8.0+ には **JIT (Just-In-Time) コンパイル** 機能があり、OpCache のバイトコードをさらに機械語まで変換して実行する仕組みがある。設定例:

```ini
opcache.jit_buffer_size = 100M
opcache.jit = tracing
```

ただし以下の理由から **本プロジェクトでは JIT を使わない方針** を採用しています。

1. **Web リクエスト中心のワークロードでは体感効果が小さい**。JIT が本領を発揮するのは CPU バウンドな計算処理 (暗号処理 / 数値計算) で、DB クエリや I/O 待ちが支配的な Laravel アプリではベンチで数 % 程度の改善にとどまる。
2. **まれにクラッシュやセグフォを起こすバグ事例** が報告されており、本番安定運用の観点でリスクが勝る。
3. JIT を有効にすると OpCache の挙動デバッグも難しくなる。

→ `php.ini` からコメントの「JITコンパイル」表記を削除し、「JIT は使わない方針」であることを明記しました。将来、画像処理やバッチ処理で CPU バウンドな処理が増えた場合は改めて検討する。

---

## 適用済みの修正内容

### ① nginx 側 `client_max_body_size` を 20M にそろえる — ✅ 適用済み

**変更ファイル**: `environment/ecr/nginx.conf`, `environment/nginx.conf` (dev / prod 両方)

`server` ブロックに以下を追加しました。これで `post_max_size = 20M` / `upload_max_filesize = 20M` が実際に機能するようになりました。

```nginx
# アップロード許容サイズ (php.ini の post_max_size / upload_max_filesize と同値)
client_max_body_size 20m;
```

dev / prod 両方に入れたのは、「本番だけアップロードが通らない」といった環境差の事故を防ぐためです。

### ② タイムゾーンを UTC に統一 — ✅ 適用済み

**変更ファイル**: `environment/ecr/php.ini`

`date.timezone` を `"Asia/Tokyo"` → `"UTC"` に変更し、Laravel `config/app.php` の `'timezone' => 'UTC'` と揃えました。これで PHP ランタイム全域 (Laravel ブート前 / ブート後 / CLI / Web 問わず) UTC で統一されます。

```ini
[Date]
date.timezone = "UTC"
```

JST 表示が必要な画面・メール等は、`Carbon::now('Asia/Tokyo')` などビュー層で変換する運用に切り替え。

### ③ タイムアウトの階層を整える — ✅ コード側は適用済み / ⚠️ インフラ側は未対応

**変更ファイル**: `environment/ecr/nginx.conf`

原則 **外側を長く、内側を短く**:

```
ALB idle timeout(75s) > nginx fastcgi_read_timeout(70s) > PHP max_execution_time(60s)
```

nginx に以下を追加しました。

```nginx
# PHP への読み取りタイムアウト
# 階層: ALB idle(75s) > nginx fastcgi_read(70s) > PHP max_execution_time(60s)
fastcgi_read_timeout 70s;
```

**残タスク**: ALB のアイドルタイムアウトを 60s (AWS デフォルト) → **75s** に上げる。これは AWS コンソールの ALB リスナー設定、または Terraform / CDK のコードで行う必要があり、本リポジトリのコードだけでは完結しません。

### ⑤ OpCache のコメントから「JITコンパイル」表記を削除 — ✅ 適用済み

**変更ファイル**: `environment/ecr/php.ini`

「OpCache (JITコンパイル) 設定」→「OpCache 設定 (高速化の要)」に書き換え、本文に「JIT は使わない方針」である旨を明記しました。詳細は本ドキュメントの **「JIT について — 本プロジェクトでは使わない方針」** セクションを参照。

## 未対応の推奨事項

### ④ `pm.max_children × memory_limit` のタスクメモリ検算 — ⚠️ 未確認

**影響範囲**: ECS タスク定義のメモリ、`environment/ecr/zz-custom.conf`

- `pm.max_children = 10` × `memory_limit = 256M` = **最大 2.5GB**
- Fargate タスクのメモリ割当が 1GB / 2GB の場合、理論上 OOM 可能性あり
- 必要な確認 / 対応:
  - タスクメモリ ≥ 3GB (OS + nginx 分も含めてバッファ) であることを AWS コンソール等で確認
  - 足りないなら `pm.max_children` を下げる (例: タスク 1GB なら 3-4 程度)

### 検討事項 (任意): `realpath_cache_size` / `realpath_cache_ttl`

Laravel のように `include` / `require` が深いフレームワークでは以下を引き上げるとわずかに改善 (`validate_timestamps = 0` と組み合わせて効く):

```ini
realpath_cache_size = 4096K
realpath_cache_ttl = 600
```

---

## 1 タスク 2 コンテナ構成としての最終判定

| 観点 | 判定 | コメント |
| --- | --- | --- |
| PHP-FPM ログが CloudWatch に届くか | ◎ | `error_log = /dev/stderr` + awslogs ドライバで成立 |
| nginx ↔ PHP-FPM の IPC 整合 | ○ | php.ini 側は listen ポートを上書きしていない (デフォルト 9000) → nginx `fastcgi_pass 127.0.0.1:9000;` と整合 |
| Fargate メモリ設計との整合 | △ | `memory_limit × pm.max_children` がタスク割当を超えないか要確認 (未対応 ④) |
| アップロード上限の一貫性 | ◎ | ✅ nginx `client_max_body_size 20m;` 追加で整合 |
| タイムゾーン一貫性 | ◎ | ✅ PHP / Laravel ともに UTC で統一 |
| タイムアウト階層 | ○ | ✅ nginx `fastcgi_read_timeout 70s;` 追加。ALB 側は未対応 |
| セキュリティ (バージョン秘匿) | ◎ | `expose_php = Off` + nginx `server_tokens off;` で整合 |
| OPcache 設定 | ◎ | ✅ JIT 非導入方針をコメントで明示 |
| セッション永続化 | ◎ | `SESSION_DRIVER=database` で ECS タスク跨ぎ対応済み (php.ini の範囲外だが関連事項として) |

→ **コード側での修正はすべて適用済み**。残るはインフラ側 (ALB idle timeout の引き上げと Fargate タスクメモリの確認) の 2 点のみ。

## まとめ: 残タスク

1. **ALB のアイドルタイムアウトを 75s に引き上げ** (AWS コンソール / Terraform / CDK — 本リポジトリのコードでは完結しない)
2. **Fargate タスクメモリが `pm.max_children × memory_limit = 2.5GB` を上回っているか確認**
   - タスク定義のメモリ割当 ≥ 3GB (nginx / OS 分も含めたバッファ込み) であること
   - 足りない場合は `zz-custom.conf` の `pm.max_children` を下げる

## 参考

### 関連ファイル

- `environment/ecr/php.ini` — 本レビュー対象
- `environment/ecr/zz-custom.conf` — `pm.max_children` など関連設定
- `environment/ecr/nginx.conf` — nginx 側の `client_max_body_size` / `fastcgi_*_timeout` (要修正)
- `docker/ecr/backend/Dockerfile` — php.ini の COPY 元 (L45)
- `backend/www/config/app.php` — Laravel タイムゾーン (`'UTC'`)
- `backend/www/config/session.php` — Laravel セッションドライバ

### 関連ドキュメント

- [PHP-FPM 設定ファイル要否ガイド](php_fpm_config.md) — 4 ファイル全体の位置付け
- [ECS / CodeDeploy デプロイ](codedeploy_ecs_deployment.md)

### 外部リンク

- [PHP Runtime Configuration](https://www.php.net/manual/ja/ini.list.php)
- [OPcache JIT 設定](https://www.php.net/manual/ja/opcache.configuration.php#ini.opcache.jit)
- [nginx `client_max_body_size`](https://nginx.org/en/docs/http/ngx_http_core_module.html#client_max_body_size)
- [ALB idle timeout](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html#connection-idle-timeout)
