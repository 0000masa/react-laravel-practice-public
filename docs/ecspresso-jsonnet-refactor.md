# ecspresso のリファクタ（Jsonnet 化 / tfstate 化 / verify-diff 追加 / イメージタグ分離）

## Context

`ecspresso/stg/` 配下の 5 つのタスク定義（web / queue-worker / migration / seeder / batch-daily-report）について以下の改善を行った：

1. **Jsonnet 化** で environment / secrets / ログ設定の重複を共通化
2. **`must_env "AWS_ACCOUNT_ID"` の排除** — SSM ARN は tfstate で、SQS_PREFIX のアカウント ID は `caller_identity` プラグインで解決
3. **`verify` / `diff` を register/deploy 前に追加**
4. **nginx と laravel のイメージタグを分離**（`IMAGE_TAG_NGINX` / `IMAGE_TAG_LARAVEL`）

このドキュメントは「なぜそうしたのか」「Jsonnet 何者なのか」「VSCode の便利ツール」「読み解き方」をまとめたもの。

---

## Jsonnet / libsonnet とは

### 一言でいうと

**Jsonnet は JSON を生成するためのデータテンプレート言語**。Google が OSS で出している小さな言語で、`if` / `for` / 関数 / `import` / オブジェクト合成などが書けて、最終的に JSON を吐き出す。YAML と並ぶ "JSON のためのデータ記述拡張" の一種。

JSON に対して：

- 変数が使える（`local x = 'foo';`）
- 関数が定義できる（`f(a, b):: a + b`）
- 他のファイルを `import` できる
- オブジェクトを `+` で合成できる（後勝ちのマージ）
- コメントが書ける（`//` `/* */`）
- 末尾カンマ OK
- 文字列クォートはシングルでもダブルでも OK

JSON は Jsonnet の部分集合なので、既存の JSON ファイルはそのまま Jsonnet として有効。

### `.jsonnet` と `.libsonnet` の違い

機能的な差は **慣習だけ**。中身の文法はどちらも同じ。

| 拡張子 | 用途 |
|---|---|
| `.jsonnet` | エントリポイント（評価して JSON を出力する側） |
| `.libsonnet` | 他のファイルから `import` されるライブラリ側 |

今回の構成だと：

```
ecspresso/stg/
  _common.libsonnet                    # ← import されるライブラリ
  web/ecs-task-def.jsonnet             # ← ここを評価すると JSON が出る
  queue-worker/ecs-task-def.jsonnet
  ...
```

エディタ・ツールはこの拡張子を見て扱いを切り替えるが、強制ではない。

### ecspresso 専用ではない

Jsonnet は ecspresso とは無関係に幅広く使われている：

- **Grafana Tanka** — Kubernetes マニフェストの記述
- **Datadog ダッシュボード** — JSON で書かれるダッシュボードの DRY 化
- **AWS CloudFormation** — テンプレートの共通化
- **Bazel ビルドファイル**

公式: <https://jsonnet.org>

---

## ecspresso は Jsonnet をサポートしているか？

**サポートしている**。ecspresso v2 は task definition / service definition のファイルを以下から自動判別する：

| 拡張子 | 扱い |
|---|---|
| `.json` | プレーン JSON。`{{ ... }}` テンプレートだけ展開 |
| `.jsonnet` | Jsonnet として評価 → JSON 化 → `{{ ... }}` テンプレート展開 |
| `.yaml` / `.yml` | YAML として読み、JSON に変換してから処理 |

つまり ecspresso 内部では「Jsonnet → JSON → ecspresso のテンプレート展開」というパイプラインが走る。`{{ tfstate ... }}` や `{{ must_env ... }}` のような Go テンプレート構文は Jsonnet のあとに評価されるので、Jsonnet 文字列の中にそのまま書いて OK。

ecspresso.yml 側の指定は `task_definition` フィールドの値だけ：

```yaml
task_definition: ecs-task-def.jsonnet  # 拡張子で自動判別
```

---

## ファイル名・拡張子のルール（必須 vs 慣習）

「`.jsonnet` / `.libsonnet` という拡張子じゃないと動かないのか？」「`_common.libsonnet` のように `_` で始める必要があるのか？」「結局 Jsonnet を解釈しているのは誰なのか？」をまとめる。

### 拡張子（.jsonnet / .libsonnet）

- **Jsonnet 言語としての必須ルールはない**。go-jsonnet は `import` 文に渡されたパスをそのままファイルとして読むだけで、拡張子で評価方法を切り替えたりはしない。極端な話 `_params.txt` でも import できる。
- **ecspresso の `task_definition:` フィールドだけは拡張子で挙動が分岐する**（前節参照）。タスク定義ファイルは `.jsonnet` にしないと Jsonnet として評価されず、`local` や `import` の構文がそのまま文字列扱いになって壊れる。逆に `.json` にすると Go テンプレート展開のみが走る。
- **`.libsonnet` 側は完全に慣習**。ecspresso からは直接参照されず、Jsonnet の `import` 経由でしか読まれないので拡張子は何でもよい。`_params.libsonnet` を `_params.json5` にリネームしても `import '../_params.json5'` で動く。
- 慣習の出所: Jsonnet コミュニティ（Grafana Tanka 等）の「entry point = `.jsonnet` / 共有ライブラリ = `.libsonnet`」というレイヤー分け。VSCode の Jsonnet Language Server (`grafana.vscode-jsonnet`) も拡張子でアクティベートするので、合わせておくとツールが効く。

### アンダースコア prefix（_common.libsonnet / _params.libsonnet）

- **Jsonnet にも ecspresso にもルールはない**。`params.libsonnet` / `common.libsonnet` にリネームして `import` 側のパスを直しても全部動く。
- 由来は Sass/SCSS の `_foo.scss`（partial = 単独でコンパイルされない、import 専用ファイル）の慣習。Jsonnet / Terraform 界隈でも踏襲されている。
- 意味するのは「これは entry point ではなく import 専用ですよ」という**読み手向けの視覚マーカー**だけ。ecspresso 側で `_` 始まりを特別扱いするロジックはない。
- 今回の構成では `task_definition:` で `ecs-task-def.jsonnet` を直接指しており、`_common.libsonnet` / `_params.libsonnet` はそこから `import` されているだけなので、prefix を外しても挙動は変わらない。

### 誰が Jsonnet を解釈しているか

- **ecspresso バイナリ本体**。ecspresso v2 は内部に [`github.com/google/go-jsonnet`](https://github.com/google/go-jsonnet) を組み込んでいて、`task_definition:` の値が `.jsonnet` なら Jsonnet 評価器を起動 → JSON にしてから Go テンプレート (`{{ tfstate ... }}` 等) を展開する。
- **GitHub Actions ランナーや `kayac/ecspresso@v2` アクション自体は Jsonnet を理解しない**。これらは「ecspresso バイナリを PATH に置く」役目しか果たしていない。
- したがってローカルで `ecspresso render --config ecspresso/stg/web/ecspresso.yml --task-definition` を叩けば、CI とまったく同じ評価パイプラインが走る（後述の「動作確認方法 → ローカル」節参照）。CI 固有の魔法ではないので、手元で挙動を再現できる。

### まとめ表

| 項目 | 必須ルール | 慣習 | 変えるとどうなるか |
|---|---|---|---|
| `task_definition:` で指すファイルの拡張子 | **`.jsonnet` / `.json` / `.yaml` のいずれか**（ecspresso が分岐） | `.jsonnet` を推奨 | `.json` にすると Jsonnet 機能（`local` / `import` 等）が使えない |
| `import` される側のファイルの拡張子 | なし | `.libsonnet` | 何でも動く（VSCode 拡張のハイライトは効かなくなる） |
| ファイル名の `_` prefix | なし | あり（partial の意味合い） | 外しても動く。読み手に entry point と紛らわしくなるだけ |
| Jsonnet を評価する主体 | ecspresso バイナリ（go-jsonnet 同梱） | — | GitHub Actions / アクション本体は無関係 |

---

## VSCode の拡張機能（Jsonnet 構文ハイライト）

**推奨: Grafana Labs の "Jsonnet Language Server"**

- マーケットプレイス ID: `grafana.vscode-jsonnet`
- インストール: VSCode で拡張機能タブから "Jsonnet" で検索 → Grafana Labs 製のものを入れる
- できること:
  - 構文ハイライト
  - エラー表示（リアルタイム）
  - 自動補完
  - `import` した先のシンボルへ "Go to Definition"
  - ホバーでドキュメント表示
  - フォーマッタ

初回起動時に `jsonnet-language-server` のバイナリ取得を促されるので、案内に従えば自動セットアップされる。

WSL/Linux 環境では WSL 拡張と組み合わせて使うのが快適。

参考: <https://github.com/grafana/vscode-jsonnet>

---

## 今回の変更内容

### ファイルレイアウト

```
ecspresso/
  _common.libsonnet              # 共通モジュール (function(p) {...} 形式) ← env 横断で共有
  stg/
    _params.libsonnet            # stg 固有値（terraform.tfvars 相当）
    web/
      ecspresso.yml
      ecs-task-def.jsonnet       # _params と _common を import して合成
    queue-worker/...
    migration/...
    seeder/...
    batch-daily-report/...
  prod/                          # 未整備（必要になったら _params.libsonnet と各タスクディレクトリを作る）
```

Terraform でいう「modules + tfvars」のパターンに対応：
- `_common.libsonnet` ＝ module 本体
- `_params.libsonnet` ＝ tfvars
- 各 `ecs-task-def.jsonnet` ＝ module 呼び出し

### 触ったファイル

| ファイル | 操作 |
|---|---|
| `ecspresso/_common.libsonnet` | 新規（params を引数に取る共通モジュール） |
| `ecspresso/stg/_params.libsonnet` | 新規（stg 固有値） |
| `ecspresso/stg/{web,queue-worker,migration,seeder,batch-daily-report}/ecs-task-def.jsonnet` | 新規（5 個） |
| `ecspresso/stg/{...}/ecs-task-def.json` | 削除（5 個） |
| `ecspresso/stg/{...}/ecspresso.yml` | 編集（task_definition 拡張子変更 / web と queue-worker は caller_identity プラグイン追加 / cluster と service をハードコード化） |
| `.github/workflows/ecspresso-update-task.yml` | 編集（入力分離 / verify+diff 追加 / AWS_ACCOUNT_ID 削除） |

`terraform/` 配下と `.github/workflows/ecs-update-laravel.yml` / `ecs-update-nginx.yml` には**手を入れていない**。後者は「ecspresso を使わないやり方」の練習用としてあえて残してある。

### Before / After（要点だけ）

#### environment 重複

**Before** — 5 ファイルすべてに同じブロックが丸コピ：

```json
{ "name": "DB_DATABASE", "value": "{{ tfstate `module.app.aws_db_instance.main.db_name` }}" },
{ "name": "DB_HOST",     "value": "{{ tfstate `module.app.aws_db_instance.main.address` }}" },
{ "name": "DB_PORT",     "value": "3306" },
...
```

**After** — `_common.libsonnet` で 1 回定義し、各 jsonnet で `c.dbEnv + c.logEnv + c.appEnv` のように合成。

#### SSM ARN

**Before** — リージョン・アカウント ID・パスがハードコード：

```json
"valueFrom": "arn:aws:ssm:ap-northeast-1:{{ must_env `AWS_ACCOUNT_ID` }}:parameter/practice/stg/db_password"
```

**After** — Terraform の data source の ARN を直接参照：

```jsonnet
{ name: 'DB_PASSWORD', valueFrom: '{{ tfstate `module.app.data.aws_ssm_parameter.db_password.arn` }}' }
```

#### SQS_PREFIX のアカウント ID

**Before**：

```json
"value": "https://sqs.ap-northeast-1.amazonaws.com/{{ must_env `AWS_ACCOUNT_ID` }}"
```

**After** — `caller_identity` プラグインで解決：

```jsonnet
{ name: 'SQS_PREFIX', value: 'https://sqs.ap-northeast-1.amazonaws.com/{{ caller_identity `Account` }}' }
```

これで `must_env "AWS_ACCOUNT_ID"` への依存がゼロに。ワークフローからも `aws sts get-caller-identity` ステップが消えた。

#### nginx / laravel イメージタグ

**Before** — 両コンテナとも同じ `IMAGE_TAG`：

```json
"image": "{{ tfstate `...nginx.repository_url` }}:{{ must_env `IMAGE_TAG` }}",
"image": "{{ tfstate `...laravel.repository_url` }}:{{ must_env `IMAGE_TAG` }}"
```

**After** — 別 env：

```jsonnet
image: '{{ tfstate `...nginx.repository_url` }}:{{ must_env `IMAGE_TAG_NGINX` }}',
image: '{{ tfstate `...laravel.repository_url` }}:{{ must_env `IMAGE_TAG_LARAVEL` }}',
```

---

## ユーザーからの質問への回答

### Q1. nginx と laravel のイメージを別々に更新できるか？

**できる**。ただし ecspresso のタスク定義は 1 ファイルで全コンテナを記述するため、片方だけ更新するときも「もう片方のコンテナのタグ」を何らかの形で指定する必要がある。

3 つの実装パターン：

| パターン | 内容 | コメント |
|---|---|---|
| A | `IMAGE_TAG_NGINX` / `IMAGE_TAG_LARAVEL` の両方を必須入力 | シンプル。ecspresso らしい。**今回採用** |
| B | 両方 input、空欄なら現行タグを `aws ecs describe-task-definition` で継承 | ロジックが複雑になる |
| C | ワークフローを 2 個に分ける | ecspresso のタスク定義は 1 ファイルなので破綻 |

### Q2. 別々のワークフロー vs 1 つのワークフロー？

**1 つのワークフローに統合し、両方のイメージタグを入力するのがベスト。**

`.github/workflows/ecs-update-laravel.yml` / `ecs-update-nginx.yml` のような分割は `aws-actions/amazon-ecs-render-task-definition` で「コンテナ単位で JSON をパッチ」できるからこそ成立する書き方。ecspresso は task-def をフルに register するので、片方のコンテナのタグだけ env で受け取って register すると「もう片方が空文字」のような壊れた状態になる。

ただし、既存の `ecs-update-laravel.yml` / `ecs-update-nginx.yml` は「ecspresso を使わない練習」のためにあえて残している。これらは ecspresso ワークフローと用途が違うので分けたままで問題なし。

---

## `_common.libsonnet` の構造解説（params を引数に取る関数）

```jsonnet
function(p) {
  // 環境変数のグループ
  dbEnv:    [...],
  logEnv:   [...],
  appEnv:   [..., { name: 'APP_NAME', value: p.appName }, { name: 'APP_ENV', value: p.appEnv }],
  otelEnv:  [..., { name: 'OTEL_SERVICE_NAME', value: p.projectName + '-backend' }, ...],
  sqsEnv:   [..., { name: 'SQS_QUEUE', value: p.sqsQueueName }, ...],
  mailEnv:  [..., { name: 'MAIL_FROM_NAME', value: p.mailFromName }, ...],
  sessionEnv: [...],

  // 派生 URL（p.frontendSubdomain + p.domain から生成）
  frontendUrl: 'https://%s.%s' % [p.frontendSubdomain, p.domain],
  backendUrl:  'https://%s.%s' % [p.backendSubdomain, p.domain],

  baseSecrets: [...],
  logGroup: '{{ tfstate `...` }}',
  awslogs(prefix):: {...},
  firelens(prefix):: {...},
  taskDefBase(family, cpu, memory):: {...},
}
```

呼び出し側：

```jsonnet
local p = import '../_params.libsonnet';
local c = (import '../../_common.libsonnet')(p);   // ← p を渡してインスタンス化
```

これで `c.appEnv` などには既に stg/prod の値が埋め込まれた状態で取れる。

### `_params.libsonnet` の中身（stg 例）

```jsonnet
{
  envName: 'stg',
  appEnv: 'staging',
  appName: 'practice',
  projectName: 'practice-stg',
  domain: 'mylabinfra.com',
  frontendSubdomain: 'www',
  backendSubdomain: 'api',
  sqsQueueName: 'staging-qrcode-generation',
  mailFromName: 'practice-stg',
}
```

prod 環境を作るときは `ecspresso/prod/_params.libsonnet` をコピーして値を書き換えるだけ。`_common.libsonnet` には触らない。

### `::`（ダブルコロン）の意味

Jsonnet では `key: value` と `key:: value` で扱いが異なる：

- `key:` — シングルコロン。出力 JSON にそのまま含まれる
- `key::` — ダブルコロン。**ヘルパ／プライベート扱い**で、最終 JSON には含まれない

関数のように呼び出して使うフィールド (`awslogs(...)` / `firelens(...)` / `taskDefBase(...)`) は `::` で定義しているので、もし誤って `_common.libsonnet` 自体を JSON に落としても関数は出力に混ざらない。

### `$` の意味

`$` は **「外側のオブジェクトのルート」** を指す。`awslogs(prefix)` の中で `$.logGroup` と書くと、`_common.libsonnet` が export しているオブジェクトのトップレベルの `logGroup` を指す。`self` だと「現在のオブジェクト」になり、ネストすると指す先がブレるので、トップレベル参照には `$` が安全。

### `function(p) { ... }` のパターン

ライブラリそのものを「関数」として export することで、import 側で引数を渡してインスタンス化する。Terraform の module 呼び出し（変数を渡す）と同じ発想。

```jsonnet
// _common.libsonnet
function(p) { foo: p.bar }

// 呼び出し側
local c = (import '_common.libsonnet')({ bar: 'value' });
// c.foo == 'value'
```

---

## `ecs-task-def.jsonnet` の書き方

例: `ecspresso/stg/web/ecs-task-def.jsonnet`

```jsonnet
local p = import '../_params.libsonnet';            // ① stg 固有値を p として読み込む
local c = (import '../../_common.libsonnet')(p);    // ② 共通モジュールに p を渡してインスタンス化

c.taskDefBase(                                       // ③ 関数を呼んで共通の骨格を取得
  '{{ tfstate `module.app.aws_ecs_task_definition.main.family` }}',
  '{{ tfstate `module.app.aws_ecs_task_definition.main.cpu` }}',
  '{{ tfstate `module.app.aws_ecs_task_definition.main.memory` }}',
) + {                                                // ④ + でオブジェクト合成
  containerDefinitions: [                            //    containerDefinitions を上書き追加
    { name: 'nginx-container', ... },
    {
      name: 'laravel-container',
      environment: c.dbEnv + c.logEnv + c.appEnv + c.otelEnv + c.sqsEnv + c.mailEnv + c.sessionEnv + [
        { name: 'FRONTEND_URL', value: c.frontendUrl },           // ⑤ 派生値も c から取れる
        { name: 'APP_URL',      value: c.backendUrl },
        { name: 'APP_DEBUG',    value: 'false' },
        { name: 'GOOGLE_REDIRECT_URI', value: c.frontendUrl + '/api/auth/google/callback' },
        ...
      ],
      secrets: c.baseSecrets + [
        { name: 'GOOGLE_CLIENT_ID', valueFrom: '...' },
        ...
      ],
      logConfiguration: c.firelens('backend/'),
    },
    ...
  ],
}
```

prod を作る時は `ecspresso/prod/web/ecs-task-def.jsonnet` を作るが、中身は **stg のものとほぼ同一**。違うのは `_params.libsonnet` の内容だけ。完全に同一でいい場合は `ecspresso/_template/web/ecs-task-def.jsonnet` を共通配置にして両環境がそれを import する形にもできる（さらに DRY）。

### `+` 演算子の意味

| 左辺 | 右辺 | 動作 |
|---|---|---|
| オブジェクト | オブジェクト | キーをマージ。同じキーがあれば右辺で上書き |
| 配列 | 配列 | 連結 |
| 文字列 | 文字列 | 結合 |

オブジェクトの `+` は深いマージではなく **トップレベルだけのマージ**である点に注意。今回はトップレベルに `containerDefinitions` を生やすだけなので問題ない。

### `local`

`local 名前 = 値;` でローカル変数を定義。`import` の戻り値もこれで受けるのが慣習。`c` という短い名前にしておくと参照箇所が読みやすい。

### `{{ ... }}` 文字列について

Jsonnet の文字列の中に `{{ tfstate ... }}` をそのまま入れているが、これは Jsonnet 的にはただの文字列。Jsonnet の評価が終わって JSON が出力されたあと、ecspresso が Go テンプレートとして 2 段目の展開を行う。

---

## tfstate プラグインと caller_identity プラグイン

`ecspresso/stg/web/ecspresso.yml`:

```yaml
plugins:
  - name: tfstate
    config:
      url: s3://github-action-terraform-tf-state-bucket/practice/laravel/stg/terraform.tfstate
  - name: caller_identity
```

| プラグイン | 役割 | 使用箇所 |
|---|---|---|
| `tfstate` | S3 の Terraform state を読み、`{{ tfstate "..." }}` で値を展開 | SSM ARN、ECR リポジトリ URL、ロググループ名、DB ホスト、S3 バケット名、CloudFront ドメイン、タスク定義の family/cpu/memory 等 |
| `caller_identity` | `sts:GetCallerIdentity` を呼んで `{{ caller_identity "Account" }}` 等を展開 | SQS_PREFIX のアカウント ID、IAM ロール ARN の組み立て |

**`caller_identity` プラグインは 5 ファイルすべてに追加**している。タスクロール／実行ロールの ARN を `arn:aws:iam::{{ caller_identity "Account" }}:role/<projectName>-execution-role` の形で組み立てるため、SQS を参照しない migration / seeder / batch にも必要。

### tfstate キーの探し方

Terraform 側のリソース名を見て `module.<モジュール名>.<resource_or_data>.<名前>.<属性>` の形で書く：

| Terraform 上の記述 | tfstate キー |
|---|---|
| `data "aws_ssm_parameter" "db_password"` (in module `app`) | `module.app.data.aws_ssm_parameter.db_password.arn` |
| `resource "aws_ssm_parameter" "otel_collector_config"` (in module `app`) | `module.app.aws_ssm_parameter.otel_collector_config.arn` |
| `resource "aws_db_instance" "main"` (in module `app`) | `module.app.aws_db_instance.main.address` |

`data` を経由する場合は `module.app.data.<...>` が必要、`resource` の場合は `module.app.<...>`（`resource.` は付かない）。otel_collector_config だけ resource 扱いなので注意。

### ローカルで tfstate のキーを探したい

```bash
ecspresso render --config ecspresso/stg/web/ecspresso.yml --task-definition
# → 展開後の JSON が標準出力される
```

または Terraform 側で直接：

```bash
terraform state show module.app.aws_ssm_parameter.otel_collector_config
```

---

## verify / diff の使い分け

ワークフローで各タスクに対して 3 ステップずつ並べている：

```yaml
- name: Verify migration
  run: ecspresso verify --config ecspresso/${{ inputs.target_env }}/migration/ecspresso.yml
- name: Diff migration
  run: ecspresso diff   --config ecspresso/${{ inputs.target_env }}/migration/ecspresso.yml
- name: Register migration task definition
  run: ecspresso register --config ecspresso/${{ inputs.target_env }}/migration/ecspresso.yml
```

| サブコマンド | 何をするか |
|---|---|
| `verify` | ECR イメージ存在 / SSM パラメータ存在 / IAM ロール / ロググループ / サブネット等を実際に Get しに行って事前チェック |
| `diff` | 現在 AWS にデプロイされているタスク定義（およびサービス定義）と、ローカルで生成したものとの差分を表示 |
| `register` | 新しいリビジョンを **登録するだけ**（サービスの更新は伴わない）。migration / seeder / batch のように単発実行系で使う |
| `deploy` | register に加えてサービスの task definition を更新（rolling / blue-green）。web / queue-worker で使う |

verify が落ちた場合は SSM パラメータ未作成や IAM 権限不足が典型。diff の出力はワークフローログに残るので、PR レビュー / 障害解析の材料になる。secrets は ARN しか含まれないので機密漏れの懸念はない。

---

## ワークフローの変更点

`.github/workflows/ecspresso-update-task.yml`：

- `inputs.IMAGE_TAG_BACKEND` → `IMAGE_TAG_NGINX` + `IMAGE_TAG_LARAVEL` の 2 入力に分割（両方 required）
- ジョブレベル `env:` で `IMAGE_TAG_NGINX` / `IMAGE_TAG_LARAVEL` を一括定義（個別 step の env ブロック撤廃）
- `aws sts get-caller-identity` ステップ削除（AWS_ACCOUNT_ID 不要のため）
- 各 ecspresso 設定（5 個）に `verify` → `diff` → `register|deploy` の 3 ステップを並べた
- 順序は migration → seeder → batch → web → queue-worker（既存と同じ）

---

## 動作確認方法

### ローカル

ローカルで `ecspresso render` / `verify` / `diff` を試すには、**ecspresso CLI が PC に入っている必要がある**。CI 側は `kayac/ecspresso@v2` アクションが自動的にバイナリをセットアップするのでインストール不要。ローカル検証をやらない場合は、後述の CI 手順だけで足りる。

#### 前提 1: ecspresso CLI のインストール

いずれか 1 つで OK。バージョンは CI と合わせて `v2.4.5` 推奨。

```bash
# 案 a) Homebrew (Mac / Linux)
brew install kayac/tap/ecspresso

# 案 b) GitHub Releases から直接 (WSL/Linux)
curl -L https://github.com/kayac/ecspresso/releases/download/v2.4.5/ecspresso_2.4.5_linux_amd64.tar.gz | tar xz
sudo mv ecspresso /usr/local/bin/
ecspresso version   # → v2.4.5

# 案 c) Go がある場合
go install github.com/kayac/ecspresso/v2/cmd/ecspresso@v2.4.5

# 案 d) aqua / asdf 等のバージョン管理ツール経由
```

#### 前提 2: AWS 認証情報

ecspresso は内部で以下を呼ぶので、これらが読める認証情報が必要：

- S3 (`tfstate` プラグインで terraform.tfstate を取得)
- STS `GetCallerIdentity` (`caller_identity` プラグイン)
- SSM `GetParameter` / ECR `DescribeImages` / IAM `GetRole` 等 (`verify` の中で使用)

`aws sso login` 済み or `~/.aws/credentials` にキーがある状態にしておく。CI で使う `AWS_ECSPRESSO_ROLE_ARN` は OIDC 経由なのでローカルではそのままは使えない。開発者用 IAM や AssumeRole で同等の read 権限を確保する。

#### 実行例

```bash
# 1. レンダリング確認（jsonnet → JSON → テンプレート展開）
IMAGE_TAG_NGINX=sha-abcdef1 IMAGE_TAG_LARAVEL=sha-abcdef1 \
  ecspresso render --config ecspresso/stg/web/ecspresso.yml --task-definition

# 2. verify: AWS 側の存在チェック
IMAGE_TAG_NGINX=sha-abcdef1 IMAGE_TAG_LARAVEL=sha-abcdef1 \
  ecspresso verify --config ecspresso/stg/web/ecspresso.yml

# 3. diff: 現在デプロイされているものとの差分
IMAGE_TAG_NGINX=sha-abcdef1 IMAGE_TAG_LARAVEL=sha-abcdef1 \
  ecspresso diff --config ecspresso/stg/web/ecspresso.yml
```

migration / seeder / batch は `IMAGE_TAG_NGINX` 不要だが、ジョブレベル env で渡しても害はない（`must_env` は参照されない限り発火しない）。

### CI

1. ブランチを切って `ecspresso-update-task` を `target_env=stg` で手動実行
2. verify / diff の各ステップが緑になることを確認
3. register/deploy 後、ECS コンソールで新リビジョンが登録され、web サービスが Blue/Green で切り替わることを確認
4. queue-worker タスクが新リビジョンで安定稼働しているか確認

ロールバック: 旧リビジョンに戻すか、`git revert` してこのワークフローを再実行。

---

## トラブルシュート: tfstate でモジュール出力が引けない

`module.app.module.ecs_task_execution_role.arn` のように **ネストした子モジュールの output** を tfstate プラグイン経由で引こうとすると、

```
template attach failed: ... error calling tfstate:
  module.app.module.ecs_task_execution_role.arn is not found in tfstate
```

で落ちる。fujiwara/tfstate-lookup（ecspresso が内部で使うライブラリ）はネストしたモジュールの `output` ブロックの値を解決できないため。

**対処**: ARN を `caller_identity` プラグインと params から自前で組み立てる。

```jsonnet
// _common.libsonnet
taskDefBase(family, cpu, memory):: {
  ...
  executionRoleArn: 'arn:aws:iam::{{ caller_identity `Account` }}:role/' + p.projectName + '-execution-role',
  taskRoleArn:      'arn:aws:iam::{{ caller_identity `Account` }}:role/' + p.projectName + '-task-role',
},
```

ロール名は `terraform/modules/app-infrastructure/iam.tf` で `${var.project_name}-execution-role` 等として固定値で命名されているので、`p.projectName` だけで一意に決まる。

これに伴い、`caller_identity` プラグインを **5 つすべての ecspresso.yml** にロードする必要がある（migration / seeder / batch も含む）。

ネストモジュールの `aws_iam_role.this[0].arn` のような **内部リソースを直接参照する** 形式（`module.app.module.ecs_task_execution_role.aws_iam_role.this[0].arn`）でも引ける可能性はあるが、モジュールの内部構造に依存して脆い（`count` ↔ `for_each` の切り替えで壊れる）ので採用しなかった。

---

## トラブルシュート: `function "tfstate" not defined`

最初は `cluster:` / `service:` フィールドにも `{{ tfstate ... }}` を書いていたが、`ecspresso verify` 実行時に以下のエラーで落ちた：

```
[ERROR] FAILED. failed to load config file ecspresso/stg/migration/ecspresso.yml:
  config parse by template failed: template: conf:2: function "tfstate" not defined
```

**原因**: `tfstate` プラグインの `{{ tfstate ... }}` 展開は **task definition ファイル内では効くが、`ecspresso.yml` 自体のフィールドでは効かない**（ecspresso v2.4.5 時点）。関連 Issue: [kayac/ecspresso#852](https://github.com/kayac/ecspresso/issues/852)。

`register` サブコマンドは `cluster` / `service` 値を一切参照しないため、これらの行のテンプレートエラーがスキップされており気付かれなかったが、`verify` / `deploy` は値を実際に使うので顕在化した。

**対処**: `ecspresso.yml` の `cluster` / `service` を**ハードコード**に変更：

```yaml
# Before（動かない）
cluster: '{{ tfstate `module.app.aws_ecs_cluster.main.name` }}'
service: '{{ tfstate `module.app.aws_ecs_service.main.name` }}'

# After（OK）
cluster: practice-stg-cluster
service: practice-stg-main-service
```

ファイルが既に `ecspresso/stg/` 配下にあり、環境ごとにディレクトリが分かれているのでハードコードでも実害はない。`tfstate` プラグインは引き続き `ecs-task-def.jsonnet` 内では正常に機能する。

環境横断で動的にしたい場合は `{{ must_env "ENV_NAME" }}` 等を使うのは可能（`must_env` は組み込み関数なのでプラグインを必要としない）：

```yaml
cluster: 'practice-{{ must_env "ENV_NAME" }}-cluster'
```

---

## 注意点

- **Terraform 側 (`ecs_web.tf` 等) との drift は意図的に許容**。Terraform は学習用途の「もう片方のやり方」として残しているが、Terraform で `aws_ecs_task_definition` の environment / secrets を更新しても ecspresso デプロイで上書きされる構造は変わらない。
- **AWS_ECSPRESSO_ROLE_ARN の権限変更は不要**。`caller_identity` プラグインは `sts:GetCallerIdentity` を使うが、これは IAM 上は誰でも呼べる。tfstate 読み出しと SSM 参照権限は既存で OK。
- **イメージタグ分離による運用変更**: workflow_dispatch 時に nginx と laravel 両方のタグを入力する必要がある。片方だけ更新する場合は、もう片方は現在稼働中のタグを ECS コンソールで確認して入力する。
- **`adot-collector` / `log-router` の image が `:latest` / `:stable`** はそのまま残している。再現性向上のためにバージョン pin したい場合は、別途タスクで対応のこと。

---

## 参考リンク

- Jsonnet 公式: <https://jsonnet.org>
- ecspresso 公式: <https://github.com/kayac/ecspresso>
- VSCode Jsonnet 拡張 (Grafana): <https://github.com/grafana/vscode-jsonnet>
- ecspresso 設定リファレンス: <https://github.com/kayac/ecspresso/blob/master/docs/Configuration.md>
