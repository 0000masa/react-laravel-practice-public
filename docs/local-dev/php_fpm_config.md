# PHP-FPM / php.ini 設定ファイルの要否ガイド

## 概要

本プロジェクトでは PHP-FPM コンテナに対して、**本番環境でのみ** 2 つの設定ファイルを COPY しています。開発環境では公式 `php:8.3-fpm` イメージのデフォルト設定のみで動作させています。

| ファイル | マウント先 / COPY 先 | 適用環境 | 本ドキュメントでの判定 |
| --- | --- | --- | --- |
| `environment/ecr/php.ini` | `/usr/local/etc/php/conf.d/custom.ini` | 本番 (ECR / ECS) | ◎ 必須 |
| `environment/ecr/zz-custom.conf` | `/usr/local/etc/php-fpm.d/zz-custom.conf` | 本番 (ECR / ECS) | ◎ 必須 |

本ドキュメントは、これらのファイルが「本当に必要なのか」「公式イメージのデフォルトではダメなのか」、そして「ECS の 1 タスク 2 コンテナ構成を考慮した設定になっているか」を整理するものです。

### 変更履歴 (ポート統一と開発環境の設定ファイル削除)

以前は開発環境にも独自の PHP-FPM 設定ファイルが 2 つありましたが、本番構成と揃えるため段階的に見直しました。

1. **PHP-FPM の listen ポートを開発・本番ともに 9000 に統一**
   - 旧: 開発 8000 / 本番 9000 (統一されておらず混乱の元)
   - 新: 両方 9000 (公式イメージデフォルト)
   - 連動変更: `environment/nginx.conf` を `fastcgi_pass laravel:9000;` に更新
   - `docker-compose.yml` の Laravel サービス側 `ports:` マッピング (旧 `8000:8000`) は削除。理由: ホスト側 9000 は MinIO が使用中で衝突するうえ、PHP-FPM は nginx コンテナから Docker 内部ネットワーク (`laravel:9000`) 経由で呼ばれるだけで、ホストから直接アクセスする必要がないため。
2. **`environment/php-fpm.conf` を削除**
   - 内容が公式 `php:8.3-fpm` イメージ同梱の `www.conf` とほぼ同一で、マウントしても挙動に差がなかったため削除。
   - `docker-compose.yml` からも該当マウント行 (`./environment/php-fpm.conf:/usr/local/etc/php-fpm.d/www.conf`) を除去。
3. **`environment/php-fpm-docker.conf` を削除**
   - 元々の存在意義は `listen = 8000` (dev 用のポートずらし) だったが、ポート 9000 統一によりその役割が消滅。残りの `daemonize = no` と `listen = 9000` はどちらも公式 `php:8.3-fpm` イメージのデフォルト (ベースイメージ同梱の `zz-docker.conf` / `www.conf`) と同じため、マウント不要と判断。
   - `docker-compose.yml` からも該当マウント行 (`./environment/php-fpm-docker.conf:/usr/local/etc/php-fpm.d/zz-docker.conf`) を除去。
   - 結果: **開発環境の PHP-FPM はベースイメージのデフォルト設定のみで動作** し、追加の設定ファイルを置いていません。

## デプロイ構成の前提 (本番)

本プロジェクトの本番環境は **AWS ECS (Fargate) に 1 タスク 2 コンテナ (サイドカー構成)** でデプロイします。この前提が設定ファイルの中身を決めているため、最初に確認します。

### 構成図

```
         ┌────────────── ECS Task (awsvpc / Fargate) ──────────────┐
         │                                                          │
 ALB ──► │  nginx-container(:80) ──► 127.0.0.1:9000 ──► backend-    │
         │                            (localhost)       container   │
         │                                              (PHP-FPM)   │
         │                   stdout/stderr ──► CloudWatch Logs      │
         └──────────────────────────────────────────────────────────┘
```

### ポイント

- **awsvpc ネットワークモード**: タスク単位で ENI と IP を持ち、タスク内の 2 コンテナは **同じ network namespace を共有**します。よって nginx → PHP-FPM は `127.0.0.1` で通信可能です。
- **nginx 設定** (`environment/ecr/nginx.conf`): `fastcgi_pass 127.0.0.1:9000;` が L16 と L22 にあります。
- **PHP-FPM の listen ポート**: `docker/ecr/backend/Dockerfile` で `EXPOSE 9000` し、公式イメージ (`php:8.2-fpm-bullseye`) のデフォルト `listen = 9000` をそのまま使用。本番では `listen` を上書きしていません。**開発環境も 9000 に統一済み**。
- **ログ**: CloudWatch Logs (`awslogs` ドライバ) に流す想定で、`stdout` / `stderr` に出力させる必要があります。

→ 本番の設定は、この ECS 2 コンテナ構成に整合するように意図的に作られています。

## 開発環境 (docker-compose) のファイル

**現在は独自の PHP-FPM 設定ファイルを置いていません**。公式 `php:8.3-fpm` イメージに同梱されている `/usr/local/etc/php-fpm.d/www.conf` と `zz-docker.conf` のデフォルト設定だけで動作します。

具体的にベースイメージが提供している挙動:

| 設定項目 | ベースイメージのデフォルト | 本プロジェクトでの期待値 | 一致? |
| --- | --- | --- | --- |
| `listen` | `9000` (`www.conf`) | `9000` (nginx から `fastcgi_pass laravel:9000;` で到達) | ✓ |
| `daemonize` | `no` (`zz-docker.conf`) | フォアグラウンド実行 | ✓ |
| `pm` | `dynamic` | 開発では `dynamic` で十分 | ✓ |
| `pm.max_children` 他 | 5 / 2 / 1 / 3 | 開発の軽い負荷想定で OK | ✓ |
| `user` / `group` | `www-data` | 開発で問題なし | ✓ |

→ デフォルト値が要件をすべて満たすので、設定ファイルを用意する必要がありません。将来チューニングが必要になった時点で、あらためて `environment/` 配下に設定ファイルを追加し `docker-compose.yml` からマウントすれば OK です。

### (参考) 以前あった設定ファイルの経緯

| ファイル | 以前の用途 | 削除理由 |
| --- | --- | --- |
| `environment/php-fpm.conf` | デフォルト `www.conf` をほぼそのままコピーしていた | 内容がデフォルトと同一で役割がなかったため |
| `environment/php-fpm-docker.conf` | `listen = 8000` で nginx の `fastcgi_pass laravel:8000;` と合わせていた | ポート 9000 統一により `listen` 上書きが不要になったため。残る `daemonize = no` もベースイメージ同梱の `zz-docker.conf` と重複 |

## 本番環境 (ECR / ECS) の 2 ファイル

### 3. `environment/ecr/php.ini` → `/usr/local/etc/php/conf.d/custom.ini`

**判定: 必須**

デフォルトの `php.ini` では本番運用要件を満たせません。特に **ECS / CloudWatch 環境では致命的な差分** があります。

| 設定 | デフォルト | 本番設定 | 理由 |
| --- | --- | --- | --- |
| `memory_limit` | `128M` | `256M` | 画像処理・バッチ処理を考慮 |
| `post_max_size` | `8M` | `20M` | nginx の `client_max_body_size` と整合 |
| `upload_max_filesize` | `2M` | `20M` | 同上。**デフォルトだと 2MB 超のアップロードが失敗する** |
| `max_execution_time` | `30` | `60` | 長時間バッチ処理対策 |
| `display_errors` | On/Off (php.ini による) | `Off` | 画面にエラーを出さない (セキュリティ) |
| `log_errors` | 未設定 | `On` | CloudWatch に流すため |
| `error_log` | 未設定 | **`/dev/stderr`** | **CloudWatch Logs (awslogs ドライバ) 連携に必須**。ローカルファイルに書いても CloudWatch には届かない |
| `expose_php` | `On` | `Off` | `X-Powered-By` ヘッダを出さない (セキュリティ) |
| `date.timezone` | `UTC` | `Asia/Tokyo` | JST 運用 |
| `mbstring.language` | `neutral` | `Japanese` | 日本語処理 |
| `mbstring.internal_encoding` | `UTF-8` | `UTF-8` | 明示 |
| `opcache.enable` | `1` | `1` | 明示 (本番は必ず有効) |
| `opcache.memory_consumption` | `128` | `128` | 明示 |
| `opcache.max_accelerated_files` | `10000` | `10000` | Laravel のファイル数に対応 (明示) |
| `opcache.validate_timestamps` | `1` | **`0`** | **本番高速化の要**。イメージはイミュータブルなので I/O を削減 |

#### デフォルトで動かすとどうなるか

- CloudWatch にエラーログが流れず、障害時に調査できない。
- 2MB を超えるファイルアップロードが `POST Content-Length of X bytes exceeds the limit` で弾かれる。
- ログやスケジューラの時刻が UTC で記録され、日本時間で読む時に都度 +9h する必要がある。
- OPcache が毎リクエストでファイル更新日時を `stat(2)` チェックするため、Disk I/O が無駄に発生する。
- レスポンスヘッダから PHP バージョンが漏れる。

### 4. `environment/ecr/zz-custom.conf` → `/usr/local/etc/php-fpm.d/zz-custom.conf`

**判定: 必須**

Fargate + 1 タスク 2 コンテナ構成で PHP-FPM を安定運用するための設定です。デフォルトの `pm = dynamic` では Fargate の固定メモリ割当と相性が悪く、OOM リスクが残ります。

| 設定 | デフォルト | 本番設定 | 理由 |
| --- | --- | --- | --- |
| `pm` | `dynamic` | **`static`** | **Fargate のメモリ固定割当に整合**。dynamic は負荷変動でメモリ使用量が揺れて OOM しやすい |
| `pm.max_children` | `5` | `10` | Fargate メモリ目安 (1GB ≒ 10 プロセス) |
| `pm.max_requests` | `0` (無限) | `1000` | メモリリーク対策で worker を定期的に再起動 |
| `pm.status_path` | 未設定 | `/status` | PHP-FPM の内部ステータスエンドポイント有効化 |
| `catch_workers_output` | `no` | **`yes`** | **worker の stdout/stderr を吸い上げて CloudWatch に流す**。これが `no` だと worker 側のエラーが消える |
| `decorate_workers_output` | `yes` | `no` | CloudWatch で読みやすく (余分なプレフィックスを付けない) |

#### デフォルトで動かすとどうなるか

- `pm = dynamic` のまま高負荷になると worker が増減し、メモリ使用量が予測しづらく Fargate の上限に触れて OOM でタスクが再起動される。
- `catch_workers_output = no` だと、worker プロセスが吐いたエラー (フレームワークのスタックトレース等) が `/dev/null` に捨てられ、CloudWatch に何も残らない。

## ECS 2 コンテナ構成との整合性チェック

| 項目 | 開発 (docker-compose) | 本番 (ECS 1 タスク 2 コンテナ) |
| --- | --- | --- |
| nginx → PHP-FPM の宛先 | `laravel:9000` (Docker ネットワーク + コンテナ名) | `127.0.0.1:9000` (awsvpc の共有 network namespace) |
| PHP-FPM の listen | `9000` (公式デフォルト / 本番と統一) | `9000` (公式デフォルト) |
| PHP-FPM の設定ファイル | なし (ベースイメージのデフォルトのみ) | `php.ini` + `zz-custom.conf` をイメージに焼き込み |
| ログ出力先 | ホストの `./logs/` にボリュームマウント | stdout / stderr → CloudWatch Logs |
| プロセス管理 | `pm = dynamic` (デフォルト) | `pm = static` |

### ポートを本番と揃えた理由

以前は開発 8000 / 本番 9000 と分かれていましたが、dev と prod で値がずれていると「どちらに合わせるか」を都度判断する必要があり、設定ミスの温床になります。**どちらかに揃えるなら公式デフォルト (9000) に合わせるのが最も素直** なので、開発側を 9000 に寄せました。結果として開発環境用の独自設定ファイルがすべて不要になり (`php-fpm.conf` / `php-fpm-docker.conf` は削除)、`environment/nginx.conf` も `fastcgi_pass laravel:9000;` に単純化されました。

### 構成を変える場合の影響 (参考)

| 別構成にした場合 | 設定変更ポイント |
| --- | --- |
| nginx と Laravel を **別タスク** に分ける | nginx 側 `fastcgi_pass` をサービスディスカバリ用 DNS に変更。PHP-FPM の `listen` を `0.0.0.0:9000` に明示 (セキュリティグループで FPM ポートを保護) |
| **Unix ソケット** 経由で IPC (共有ボリューム必要) | `zz-custom.conf` に `listen = /var/run/php-fpm.sock` を追加。nginx 側 `fastcgi_pass unix:/var/run/php-fpm.sock;`。2 コンテナ間で `emptyDir` 相当の共有ボリュームをマウント |
| EC2 launch type に変更 | 基本 `awsvpc` と同様だが、ネットワークモードを `bridge` にするなら `127.0.0.1` 通信は成立しないため `links` / `depends_on` で繋ぐ必要あり。現設定のままで良い理由が消えるので見直し必要 |

## 「ECS 向けの設定」という観点の要点

本番で入れている設定が「なぜ ECS 向けに必要か」を一言でまとめると、次の 6 点です。

1. **IPC は `127.0.0.1`**: awsvpc ではタスク内のコンテナが network namespace を共有するため、コンテナ名や Docker ネットワークではなく localhost で通信します (docker-compose 環境と別物)。
2. **listen ポートは 9000 (公式デフォルト)**: 本番は上書きしていないため、公式イメージの挙動にそのまま乗っています。
3. **ログは stdout / stderr に出す**: `awslogs` ドライバ (または FireLens) 前提。ローカルファイルは CloudWatch に届きません。`error_log = /dev/stderr` と `catch_workers_output = yes` がこの要件を満たします。
4. **プロセス管理は `static` 化**: Fargate はメモリが固定リソースなので、`static` + `pm.max_children` 固定のほうがメモリ使用量を読みやすく、OOM を避けやすくなります。
5. **OPcache 有効 + タイムスタンプチェック無効化**: イメージがイミュータブルなので、`opcache.validate_timestamps = 0` で I/O を削減できます。
6. **ヘルスチェックは nginx 経由**: ALB のターゲットは `nginx-container:80` です。PHP-FPM の `/status` や `/ping` は ALB から直接叩かれません。`environment/ecr/nginx.conf` の `location = /api/health` がアプリケーションヘルスチェックを中継します。

## まとめ: 「デフォルト設定でいいのか」判定

| ファイル | デフォルトで動くか | 判定 | 備考 |
| --- | --- | --- | --- |
| `php-fpm.conf` (dev) | — | **削除済み** | 公式イメージ同梱 `www.conf` と同内容のため 2026-04-23 に削除 |
| `php-fpm-docker.conf` (dev) | — | **削除済み** | ポート統一 (9000) で `listen` 上書きが不要になり、残る設定もベースイメージのデフォルトと同じだったため 2026-04-23 に削除 |
| `php.ini` (prod) | 動くが運用に支障 | **必須** | ログが CloudWatch に届かない、アップロード上限 2MB、JST 未設定、OPcache 未最適化 |
| `zz-custom.conf` (prod) | 動くが Fargate で OOM リスク・ログ欠落 | **必須** | `pm = static` 化と `catch_workers_output = yes` が Fargate 安定運用の要 |

## 参考

### 関連ファイル

- `docker-compose.yml` — 開発環境のサービス定義 (`laravel` サービスは PHP-FPM 設定ファイルをマウントせずデフォルトで動作。`ports:` 公開もなく、nginx とは内部ネットワーク経由で通信)
- `docker/ecr/backend/Dockerfile` — 本番 PHP-FPM イメージ (`php.ini` / `zz-custom.conf` を COPY)
- `docker/ecr/nginx/Dockerfile` — 本番 nginx イメージ
- `environment/nginx.conf` — 開発環境の nginx 設定 (`fastcgi_pass laravel:9000;`)
- `environment/ecr/nginx.conf` — 本番環境の nginx 設定 (`fastcgi_pass 127.0.0.1:9000;`)

### 関連ドキュメント

- [ECS / CodeDeploy デプロイ](codedeploy_ecs_deployment.md)
- [環境変数設定ガイド](environment_setup.md)

### 外部リンク

- [PHP-FPM 設定リファレンス](https://www.php.net/manual/ja/install.fpm.configuration.php)
- [OPcache チューニング](https://www.php.net/manual/ja/opcache.configuration.php)
- [AWS Fargate タスクサイズ](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_size)
- [AWS awslogs ログドライバ](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_awslogs.html)
