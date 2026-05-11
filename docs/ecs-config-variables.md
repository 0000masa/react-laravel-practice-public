# ECS スペック・スケール設定の変数化 / Capacity Provider Strategy

## 概要

`modules/app-infrastructure/ecs_web.tf` / `ecs_queue.tf` / `ecs_tasks.tf` / `event_bridge.tf` に直書きされていた以下の設定を、サービス/タスク単位の `object` 型変数に集約した。

- ECS サービスの `desired_count`
- AutoScaling の `min_capacity` / `max_capacity` / `cpu_target_value` / `memory_target_value`
- タスク定義の `cpu` / `memory`
- ECS ネイティブ Blue/Green デプロイの `bake_time_in_minutes`
- `launch_type = "FARGATE"` を **`capacity_provider_strategy` に置き換え**、Fargate / Fargate Spot を環境別に切り替え可能に

これにより stg は低コスト（小スペック・Spot 100%）、prod は高可用性（大スペック・オンデマンド主体）といった環境別の最適化が、`terraform.tfvars` の値変更だけで実現できる。

## 変数の構成

### 設計方針

「terraform.tfvars を見たときにどのサービス/タスクの設定か一目でわかる」ことを優先し、**サービス/タスクの役割ごとに別変数** に分割した。RDS で採用した `rds_config` の単一 object パターンとは意図的に異なる。

| 変数名 | 対象 |
|---|---|
| `ecs_web_service_config` | Web サービス（nginx + laravel + log-router + adot-collector）|
| `ecs_queue_worker_service_config` | Queue Worker サービス（Laravel queue:work）|
| `ecs_runner_task_config` | Runner タスク（migrate / seed / 任意 shell コマンド共通、`db-task.yml` から containerOverrides で切替）|
| `ecs_batch_daily_report_task_config` | 日次バッチタスク（EventBridge 起動）|

### 変数の中身

#### `ecs_web_service_config`

```hcl
{
  cpu                  = string  # タスクCPU "256"/"512"/"1024"/"2048"/"4096"
  memory               = string  # タスクメモリ MiB（cpuに応じた組合せ要）
  desired_count        = number  # 起動タスク数の初期値
  bake_time_in_minutes = number  # Blue/Green 切替後に Blue を残す時間（分）。0〜10080
  capacity_provider_strategy = list(object({
    capacity_provider = string  # "FARGATE" or "FARGATE_SPOT"
    weight            = number
    base              = number
  }))
  autoscaling = object({
    min_capacity        = number  # スケール下限
    max_capacity        = number  # スケール上限
    cpu_target_value    = number  # CPU使用率目標(%)。超過でスケールアウト
    memory_target_value = number  # メモリ使用率目標(%)
  })
}
```

#### `ecs_queue_worker_service_config`

`ecs_web_service_config` から `autoscaling` を除いた構造（キューワーカーは現状 AutoScaling 未設定）。

#### `ecs_runner_task_config`

```hcl
{
  cpu    = string
  memory = string
}
```

GitHub Actions の `db-task.yml` から `aws ecs run-task` で起動する想定のため、`launch_type` / `capacity_provider` は **実行時の引数で指定**。タスク定義側は CPU / メモリのみ。実際に走るコマンド（`php artisan migrate --force` / `php artisan db:seed --force` / `bash -lc "<任意コマンド>"`）は `containerOverrides` で実行時に渡されるため、タスク定義に `command` は持たせていない。

#### `ecs_batch_daily_report_task_config`

```hcl
{
  cpu    = string
  memory = string
  capacity_provider_strategy = list(object({
    capacity_provider = string
    weight            = number
    base              = number
  }))
}
```

EventBridge ルールの `ecs_target` で `capacity_provider_strategy` を適用する。

## Capacity Provider Strategy

### `launch_type` から `capacity_provider_strategy` への移行理由

`launch_type` は `"FARGATE"` または `"EC2"` の **2 値** しか受け付けず、Fargate Spot を選択できない。Fargate Spot を使うには `capacity_provider_strategy` に切り替える必要があるため、両方を扱える後者に統一した。

### `aws_ecs_cluster_capacity_providers` の登録

クラスタで `capacity_provider_strategy` を使うには、事前にどの provider を許可するかをクラスタに登録する必要がある。`modules/app-infrastructure/ecs_web.tf` で定義:

```hcl
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}
```

両方を有効化しておけば、tfvars 側のストラテジーで重み 0 にするだけで切替できる（環境ごとに登録内容を変える必要がない）。

### `capacity_provider`

利用するキャパシティプロバイダの名前。Fargate では以下の 2 つ:

| 値 | 内容 |
|---|---|
| `FARGATE` | オンデマンド。料金は通常価格、停止リスクなし |
| `FARGATE_SPOT` | スペアキャパシティを最大 70% 引きで利用。AWS 側の容量都合で **2 分前通知で停止** される可能性あり |

### `base`

そのプロバイダで **最低限確保するタスク数**。

- 戦略全体で **1 つのプロバイダにのみ** 設定可能（複数指定はエラー）
- 例: `FARGATE` に `base = 2` → 最初の 2 タスクは必ず FARGATE で起動
- Spot のみでは不安な prod で「最低 N 台はオンデマンドで土台を確保」したい場合に使う

### `weight`

`base` を満たした **後の追加タスク** をプロバイダ間でどう配分するかの **比率**。数値そのものに意味はなく、他プロバイダとの比で決まる。

- 例: `FARGATE: weight=1` / `FARGATE_SPOT: weight=4` → base 充足後は **FARGATE 1 : FARGATE_SPOT 4** の比率（≒ Spot 80% / On-demand 20%）

### 戦略パターン例

#### stg: 完全 Spot（コスト最優先）

```hcl
capacity_provider_strategy = [
  { capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 }
]
```

すべてのタスクが Spot で起動。停止リスクはあるが、コストは最大 70% 削減。

#### prod 推奨: 土台はオンデマンド、追加分は Spot 寄せ

```hcl
capacity_provider_strategy = [
  { capacity_provider = "FARGATE",      weight = 1, base = 2 },
  { capacity_provider = "FARGATE_SPOT", weight = 4, base = 0 }
]
```

- 最初の 2 タスクは必ず FARGATE（Spot 全滅でも最低 2 台は維持）
- 3 タスク目以降は FARGATE 1 : FARGATE_SPOT 4 の比率で増える
- スケール時の追加分はほぼ Spot に流れる

#### prod 保守的: 完全オンデマンド

```hcl
capacity_provider_strategy = [
  { capacity_provider = "FARGATE", weight = 1, base = 0 }
]
```

可用性最優先。Spot の停止リスクを許容しないケース。

## `bake_time_in_minutes`（Blue/Green ロールバック猶予）

ECS ネイティブ Blue/Green デプロイ（`deployment_configuration.strategy = "BLUE_GREEN"`）で、**新（Green）にトラフィックを切り替えた後、旧（Blue）タスクをすぐ消さずに待機させる時間（分）**。この間に CloudWatch アラームやヘルスチェックで異常が検知されれば、`deployment_circuit_breaker.rollback = true` と組み合わせて自動的に Blue へ戻せる。

- **範囲**: 0 〜 10080（7 日）
- **0**: stg 向け。切替直後に Blue を破棄。デプロイサイクルが最短になる（失敗してもユーザー影響なし）。自動ロールバックの猶予はなし
- **5〜10**: 軽くデプロイ完走を観測したい場合
- **30〜60**: prod 向け。アラーム発火や P1 検知に時間がかかるため、Blue を残しておくと安全
- **数時間〜数日**: 重要度の高い prod や、人手によるカナリア観測を挟みたいケース

### 環境別の推奨値

| 環境 | 推奨値 | 理由 |
|---|---|---|
| stg | 0 | デプロイサイクルを最短にしたい。失敗してもユーザー影響なし |
| prod | 30〜60 | アラート発火・自動ロールバックの猶予を確保 |

## tfvars の設定例

### stg（現行・コスト優先）

```hcl
# stg/terraform.tfvars
ecs_web_service_config = {
  cpu                  = "1024"
  memory               = "2048"
  desired_count        = 1
  bake_time_in_minutes = 0
  capacity_provider_strategy = [
    { capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 }
  ]
  autoscaling = {
    min_capacity        = 1
    max_capacity        = 6
    cpu_target_value    = 60
    memory_target_value = 70
  }
}

ecs_queue_worker_service_config = {
  cpu           = "256"
  memory        = "512"
  desired_count = 1
  capacity_provider_strategy = [
    { capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 }
  ]
}

ecs_runner_task_config = { cpu = "256", memory = "512" }

ecs_batch_daily_report_task_config = {
  cpu    = "256"
  memory = "512"
  capacity_provider_strategy = [
    { capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 }
  ]
}
```

### prod 例（高可用性優先）

```hcl
# prod/terraform.tfvars （将来作成時の例）
ecs_web_service_config = {
  cpu                  = "2048"
  memory               = "4096"
  desired_count        = 2
  bake_time_in_minutes = 30   # アラーム検知・自動ロールバックの猶予を確保
  capacity_provider_strategy = [
    { capacity_provider = "FARGATE",      weight = 1, base = 2 },
    { capacity_provider = "FARGATE_SPOT", weight = 4, base = 0 }
  ]
  autoscaling = {
    min_capacity        = 2
    max_capacity        = 10
    cpu_target_value    = 50
    memory_target_value = 60
  }
}

ecs_queue_worker_service_config = {
  cpu           = "512"
  memory        = "1024"
  desired_count = 2
  capacity_provider_strategy = [
    { capacity_provider = "FARGATE", weight = 1, base = 0 }
  ]
}

ecs_runner_task_config = { cpu = "512", memory = "1024" }

ecs_batch_daily_report_task_config = {
  cpu    = "512"
  memory = "1024"
  capacity_provider_strategy = [
    { capacity_provider = "FARGATE", weight = 1, base = 0 }
  ]
}
```

## 変数の追加 / 変更手順

新しい属性（例: `deployment_minimum_healthy_percent` を変数化したい）を追加するときの流れ:

1. `modules/app-infrastructure/variables.tf` の対象 object 型変数に属性を追加（heredoc description も更新）
2. `modules/app-infrastructure/ecs_*.tf` のリソースで `var.<config>.<新属性>` を参照
3. `stg/variables.tf` の object 型に同じ属性を追加（description は簡略でOK）
4. `stg/terraform.tfvars` で値を設定（**default は置かない**ため必須）
5. `terraform plan` で差分を確認

> **注意**: 環境差のある変数は default を置かず、必ず tfvars で必須記述させる方針。default を置くと prod 環境で stg 用の値が紛れ込む事故を防げない。

## 適用時の注意

- `launch_type` から `capacity_provider_strategy` への切替は、ECS サービスを **置換扱い**（`-/+ destroy and then create replacement`）にする可能性がある。`terraform plan` の差分を必ず確認する
- ECS ネイティブ Blue/Green デプロイ（`deployment_configuration` の `strategy = "BLUE_GREEN"`）は `capacity_provider_strategy` と併用可能
- `aws_ecs_cluster_capacity_providers` は AWS 側で暗黙作成されている場合 import が必要になる場合がある

## 関連ファイル

| ファイル | 内容 |
|---|---|
| `modules/app-infrastructure/variables.tf` | 5変数の定義（heredoc description あり） |
| `modules/app-infrastructure/ecs_web.tf` | Web サービス + クラスタ + capacity providers |
| `modules/app-infrastructure/ecs_queue.tf` | Queue Worker サービス |
| `modules/app-infrastructure/ecs_tasks.tf` | Migration / Seeder / Batch タスク定義 |
| `modules/app-infrastructure/event_bridge.tf` | 日次バッチ起動の capacity_provider_strategy |
| `stg/variables.tf` | ルート側の変数再宣言 |
| `stg/terraform.tfvars` | stg の値 |
| `stg/main.tf` | モジュール呼び出し |
