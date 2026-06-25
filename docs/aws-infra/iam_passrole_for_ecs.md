# `iam:PassRole` とは何か — ECS タスク起動を例に

## 概要

ECS のタスクを起動・更新するには「タスクが引き受けるロール」を ECS に渡す必要があり、そのときに `iam:PassRole` 権限が要る。`AdministratorAccess` を付けたロールやユーザーで作業しているときには **無意識に** この権限が通っているが、最小権限化（このリポジトリでは GitHub Actions のロールが該当）する際には **明示的に書く必要がある**。

このドキュメントでは:

- `iam:PassRole` が何をしている権限か
- なぜ ECS タスクを起動するのに必要か
- これまで「Terraform apply で ECS タスクを作る」「コンソールでタスクを起動する」が動いていた仕組み
- 最小権限化したロールで `iam:PassRole` を書く意味

を整理する。

---

## 1. ECS タスクに紐づく 2 つの IAM ロール

ECS タスクには通常 2 種類のロールが紐づく。

| ロール | 誰が使うか | 主な用途 |
|---|---|---|
| **Task Execution Role** (`*_execution_role`) | ECS エージェント自身 | ECR からイメージを pull、SSM Parameter Store から secret を取得、CloudWatch Logs にログを書き込む |
| **Task Role** (`*_task_role`) | コンテナ内で動くアプリ（Laravel など） | アプリが S3 にファイルを置く、SES でメール送信、SQS にメッセージ送信などをするときの権限 |

このリポジトリで言うと、`modules/app-infrastructure/iam.tf` の以下の 2 つ:

- `module.ecs_task_execution_role` → `practice-stg-execution-role`
- `module.ecs_task_role` → `practice-stg-task-role`

これらは「ECS タスクの中身が引き受ける権限」であり、**強い権限を持っていることが多い**。

---

## 2. 「ロールを渡す」操作とは

ECS の以下の API では、引数として **ロール ARN を指定する**:

| API | ロールを指定する場面 |
|---|---|
| `ecs:RegisterTaskDefinition` | タスク定義を登録するとき、`taskRoleArn` と `executionRoleArn` を指定 |
| `ecs:RunTask` | 単発タスクを起動するとき、タスク定義に書かれたロールが ECS に渡される |
| `ecs:UpdateService` | サービスの新リビジョンを作るとき、タスク定義経由で同様 |

API を呼び出した側（人 / GitHub Actions / Terraform）は、「自分が指定するロール ARN を ECS というサービスに **使わせていい**」という許可を持っている必要がある。
この許可が `iam:PassRole`。

---

## 3. なぜ `iam:PassRole` というチェックが存在するのか

シナリオを考える:

> ある社員が `ecs:RunTask` だけを持つロールを引き受けていたとする。
> もし `iam:PassRole` のチェックが無ければ、この社員は **AdministratorAccess を持つ別のロール** を ECS タスクに紐づけて起動できる。
> 起動したコンテナの中から AWS API を呼べば、結果として AdministratorAccess で何でもできてしまう。

これは **権限昇格 (privilege escalation) 攻撃** の典型パターン。

`iam:PassRole` は「ロールをサービスに紐づける行為」そのものを別の権限として切り出すことで、これを防いでいる:

- API 呼び出し側は **「RunTask の権限」と「PassRole の権限」の両方** を持っていないといけない
- `Resource` を限定しておけば、「この 2 つのロールしか ECS に渡せない」と縛れる

---

## 4. これまで Terraform apply / コンソール操作で ECS タスクを作れていた理由

ユーザーの最初の理解（要約）:

> GitHub Actions 経由で `terraform apply` で ECS のタスクを建てたり、AWS コンソールでタスクを建てたりできるのは、
> - Terraform の場合は AssumeRole で `AdministratorAccess`
> - コンソールの場合はログインしている人の権限が `AdministratorAccess`
>
> で、タスクにタスク実行ロールとタスクロールを与える権限（= `iam:PassRole`）があるから、ということ？

**結論: ほぼその理解で正しい。**

`AdministratorAccess` の policy は中身が `Action: "*"`, `Resource: "*"` なので、`iam:PassRole` も含めた **すべての IAM API** を任意のロールに対して呼べる。これにより:

| 経路 | 動いていた仕組み |
|---|---|
| Terraform apply（AssumeRole で `AdministratorAccess`） | Terraform が `aws_ecs_task_definition` を `RegisterTaskDefinition` で作るとき、`task_role_arn` / `execution_role_arn` を ECS に渡す → `iam:PassRole` が必要 → `AdministratorAccess` に含まれているので通る |
| AWS コンソール（管理者ユーザー） | コンソールの内部処理が同じ `RegisterTaskDefinition` API を叩いている。ログインユーザーが `AdministratorAccess` 相当なので同様に通る |
| GitHub Actions（旧 `secrets.AWS_ROLE_ARN`） | これも従来は `AdministratorAccess` 相当の広い権限のロールを引き受けていたため、`iam:PassRole` が暗黙に許可されていた |

つまり、これまで **「PassRole を意識しなくても動いていた」のは、使っていたロールが広すぎたから**、ということになる。

### 補足: Terraform 自身に PassRole が必要なのは「タスク定義を作るとき」だけ

Terraform で IAM ロールそのもの（`aws_iam_role`）を作るのには `iam:PassRole` は不要（`iam:CreateRole` 等が必要）。
PassRole が要るのは **そのロール ARN を別のリソースに紐づける場面** のみ:

- `aws_ecs_task_definition` の `task_role_arn` / `execution_role_arn`
- `aws_lambda_function` の `role`
- `aws_eventbridge_target` の `role_arn`（このリポジトリの batch task に該当）
- `aws_iam_instance_profile` 経由で EC2 にロールを付ける場合 など

---

## 5. 最小権限化したロールで `iam:PassRole` を明示する

このリポジトリでは GitHub Actions 用に最小権限ロールを作った（`modules/app-infrastructure/iam_github_actions.tf` / `iam_policy_github_actions.tf`）。
広い `AdministratorAccess` から離れた以上、**`iam:PassRole` を明示的に書かないと ECS タスクの登録・起動ができない**。

該当ブロック（`gha_ecs_update_main_service_policy` の例）:

```hcl
{
  Sid    = "PassEcsTaskRoles"
  Effect = "Allow"
  Action = ["iam:PassRole"]
  Resource = [
    module.ecs_task_execution_role.arn,
    module.ecs_task_role.arn
  ]
  Condition = {
    StringEquals = {
      "iam:PassedToService" = "ecs-tasks.amazonaws.com"
    }
  }
}
```

各要素の意味:

| フィールド | 意味 |
|---|---|
| `Action: ["iam:PassRole"]` | 「ロールをサービスに渡す」操作の許可 |
| `Resource = [execution_role.arn, task_role.arn]` | 渡してよい **ロールはこの 2 つだけ**。他のロール（例: 別アプリの task role や Administrator ロール）は渡せない |
| `Condition.iam:PassedToService = "ecs-tasks.amazonaws.com"` | 渡してよい **相手は ECS タスクサービスだけ**。Lambda や EC2 などには使えない（二重ロック） |

これにより、たとえ GitHub Actions のロールが奪取されても:

- 別アカウント・別アプリの IAM ロールは ECS に渡せない
- このアプリのタスクロールでも、Lambda や EC2 に流用できない

という二重防御が効く。

---

## 6. どのワークフロー / 操作で `iam:PassRole` が要るか（このリポジトリ）

| ワークフロー / 操作 | PassRole 必要 | 理由 |
|---|:-:|---|
| `ecs-update-laravel.yml` / `ecs-update-nginx.yml` / `ecs-update-laravel-que.yml` | ✅ | `RegisterTaskDefinition` で `taskRoleArn` / `executionRoleArn` を指定 |
| `db-task.yml` | ✅ | `RunTask` で runner タスクを起動するとき、タスク定義のロールを ECS に渡す（migrate / seed / shell すべて） |
| `ecspresso-update-task.yml` | ✅ | ecspresso が内部で `RegisterTaskDefinition` + `UpdateService` を呼ぶ |
| `ecr-deploy-laravel.yml` / `ecr-deploy-nginx.yml` | ❌ | ECR への push のみ。ECS タスクは触らない |
| `s3-deploy-frontend.yml` | ❌ | S3 sync + CloudFront invalidation のみ |
| `terraform apply`（運用者が AssumeRole で実行） | ✅ | `aws_ecs_task_definition` 作成時に PassRole が必要。AdministratorAccess に含まれているため意識せず動く |
| AWS コンソールで「タスクを実行」「サービスを更新」 | ✅ | 内部で同じ ECS API を呼ぶため。管理者権限なら意識せず動く |

ECR push や S3 sync 系のワークフロー / ロールに PassRole が無いのは、それらが ECS タスクを操作しないため。

---

## 7. まとめ

- ECS のタスク定義登録 / タスク起動には、**タスクが引き受けるロール (execution role / task role) を ECS に渡す** 操作が必ず含まれる
- この「渡す」を許可するのが `iam:PassRole`
- これまで `terraform apply` やコンソール操作で意識せず動いていたのは、**使っていた権限が `AdministratorAccess` だったため `iam:PassRole` が暗黙に含まれていた** から
- GitHub Actions のロールを最小権限化するなら、PassRole は **明示的に書く必要がある**
- Resource を限定 + `iam:PassedToService` 条件を併用することで、権限昇格や横展開を防ぐ
