# CodeDeploy方式によるECS Blue/Greenデプロイ（参考）

## 概要

このリポジトリの現在の ECS デプロイでは **CodeDeploy を使っていない**。

- 現行方式: `.github/workflows/ecspresso-update-task.yml` から `ecspresso deploy`
- web サービス: ECS ネイティブ Blue/Green（`deploymentConfiguration.strategy = "BLUE_GREEN"`）
- queue-worker サービス: ECS 標準の Rolling Update
- CodeDeploy 用の `appspec.json` は現行構成では参照されないため、リポジトリには置かない

このドキュメントは、ECS がネイティブ Blue/Green に対応する前に使われていた **CodeDeploy 方式の Blue/Green デプロイを再構成する場合の参考資料** として残す。実運用の現行パイプラインは [ecspresso デプロイパイプライン解説](./ecspresso-deployment-pipeline.md) を参照する。

---

ECSサービスのデプロイ方式には主に以下の3つがある。

| 方式 | deploymentController | 特徴 |
|---|---|---|
| Rolling Update | `ECS` | ECSが直接タスクを入れ替える。最もシンプル |
| ECS組み込みBlue/Green | `ECS` | ECSネイティブのBlue/Green。`UpdateService` APIで更新可能 |
| CodeDeploy方式Blue/Green | `CODE_DEPLOY` | CodeDeployがトラフィック切替を管理。テストリスナーによる検証やカナリアリリースが可能 |

このリポジトリの web サービスは現在、2行目の **ECS組み込みBlue/Green** を使っている。3行目の **CodeDeploy方式Blue/Green** を使う場合は、ECSサービスの `deploymentController` を `CODE_DEPLOY` にし、CodeDeployアプリケーション、デプロイメントグループ、AppSpec、GitHub Actions側のCodeDeploy呼び出しを追加する必要がある。

---

## 現行構成との違い

| 項目 | 現行構成 | CodeDeploy方式にする場合 |
|---|---|---|
| デプロイ実行主体 | ECS + ecspresso | CodeDeploy |
| ECSサービスの `deploymentController` | `ECS` | `CODE_DEPLOY` |
| Blue/Green設定 | `ecspresso/stg/web/service-def.jsonnet` の `deploymentConfiguration.strategy = "BLUE_GREEN"` | CodeDeployデプロイメントグループ |
| タスク定義更新 | `ecspresso deploy` | `amazon-ecs-deploy-task-definition` などから CodeDeploy `CreateDeployment` |
| AppSpec | 不要 | 必要 |
| ルート `appspec.json` | 置かない | 必要になった時点で追加する |

現行の web サービス定義は `ecspresso/stg/web/service-def.jsonnet` にあり、`loadBalancers[].advancedConfiguration` で本番リスナールール、テストリスナールール、代替ターゲットグループ、ECS が ALB を操作するためのロールを指定している。CodeDeploy方式では、このあたりの切り替え制御をCodeDeployデプロイメントグループ側が担う。

---

## AppSpecの例

### 役割

CodeDeploy方式のECS Blue/Greenでは、AppSpecファイルが **CodeDeployにデプロイ対象を伝える設定ファイル** になる。CodeDeployはこのファイルを読み取り、どのECSサービスに対して、どのタスク定義で、どのコンテナ・ポートにトラフィックを向けるかを判断する。

現在のリポジトリには AppSpec ファイルを置かない。もし CodeDeploy 方式を使うことになった場合だけ、例えば `appspec.codedeploy.json` や `deploy/codedeploy/appspec.json` のように用途が分かる名前・場所で追加する。

### 記述例

```json
{
  "version": 0.0,
  "Resources": [
    {
      "TargetService": {
        "Type": "AWS::ECS::Service",
        "Properties": {
          "TaskDefinition": "<TASK_DEFINITION>",
          "LoadBalancerInfo": {
            "ContainerName": "nginx-container",
            "ContainerPort": 80
          }
        }
      }
    }
  ]
}
```

### 各フィールドの説明

| フィールド | 説明 |
|---|---|
| `version` | AppSpecのバージョン。ECSの場合は `0.0` 固定 |
| `Resources` | デプロイ対象のリソース定義の配列 |
| `TargetService.Type` | `AWS::ECS::Service` 固定 |
| `TaskDefinition` | デプロイするタスク定義のARN。`<TASK_DEFINITION>` というプレースホルダーを記述しておくと、GitHub Actionsの `amazon-ecs-deploy-task-definition` アクションが新しいタスク定義ARNに置換できる |
| `ContainerName` | ALBのターゲットグループに紐づくコンテナ名。本プロジェクトではnginxがリクエストを受けるため `nginx-container` を指定 |
| `ContainerPort` | ALBからトラフィックを受けるポート番号 |

---

## GitHub Actionsワークフロー例

### 役割

現行リポジトリには CodeDeploy 用ワークフローは存在しない。もし CodeDeploy 方式を使う場合は、GitHub Actionsから手動トリガー（`workflow_dispatch`）でBackendコンテナのイメージを更新し、**CodeDeploy経由でBlue/Greenデプロイ**を実行するワークフローを追加する。

### 環境変数

| 変数名 | 説明 |
|---|---|
| `AWS_ROLE_ARN` | OIDC認証で使用するIAMロールのARN（GitHub Secretsに格納） |
| `AWS_REGION` | AWSリージョン（`ap-northeast-1`） |
| `IMAGE_TAG_BACKEND` | デプロイするBackendイメージのタグ（手動入力） |
| `ECS_TASK_DEF` | ECSタスク定義のファミリー名 |
| `CONTAINER_NAME_BACKEND` | タスク定義内のBackendコンテナ名 |
| `ECS_CLUSTER` | ECSクラスター名 |
| `ECS_SERVICE` | ECSサービス名 |
| `ECR_REPO_BACKEND` | BackendイメージのECRリポジトリ名 |
| `CODEDEPLOY_APPLICATION` | CodeDeployアプリケーション名 |
| `CODEDEPLOY_DEPLOYMENT_GROUP` | CodeDeployデプロイメントグループ名 |

### 処理の流れ

```
1. ソースコードを取得（actions/checkout）
        ↓
2. AWS OIDC認証
        ↓
3. AWSアカウントIDを取得
        ↓
4. 現在のタスク定義JSONをAWSからダウンロード
        ↓
5. タスク定義内のBackendコンテナのイメージURIを新しいタグに書き換え
        ↓
6. 新しいタスク定義を登録し、CodeDeployでBlue/Greenデプロイを開始
```

### 各ステップの詳細

#### 1. ソース取得

```yaml
- uses: actions/checkout@v4
```

CodeDeploy用のAppSpecをリポジトリから取得するために必要。

#### 2. AWS OIDC認証

```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ env.AWS_ROLE_ARN }}
    aws-region: ${{ env.AWS_REGION }}
```

GitHub ActionsのOIDCトークンを使ってAWSの認証を行う。アクセスキーを使わないセキュアな方式。

#### 3. AWSアカウントID取得

```yaml
- name: Get AWS account ID
  run: |
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "ACCOUNT_ID=${ACCOUNT_ID}" >> $GITHUB_ENV
```

ECRのイメージURIを組み立てるためにアカウントIDを取得する。

#### 4. タスク定義のダウンロード

```yaml
- name: Download task definition
  run: |
    aws ecs describe-task-definition --task-definition ${{ env.ECS_TASK_DEF }} \
    --query taskDefinition > task-definition.json
```

現在のACTIVEなタスク定義をベースにし、コンテナイメージだけを差し替える。

#### 5. イメージURIの書き換え

```yaml
- name: Render backend container
  uses: aws-actions/amazon-ecs-render-task-definition@v1
  with:
    task-definition: task-definition.json
    container-name: ${{ env.CONTAINER_NAME_BACKEND }}
    image: <アカウントID>.dkr.ecr.<リージョン>.amazonaws.com/<リポジトリ名>:<タグ>
```

タスク定義JSON内の指定コンテナのイメージURIを新しいものに置換する。

#### 6. CodeDeployによるデプロイ

```yaml
- name: Deploy Amazon ECS task definition
  uses: aws-actions/amazon-ecs-deploy-task-definition@v2
  with:
    task-definition: ${{ steps.render-backend.outputs.task-definition }}
    service: ${{ env.ECS_SERVICE }}
    cluster: ${{ env.ECS_CLUSTER }}
    wait-for-service-stability: true
    codedeploy-appspec: deploy/codedeploy/appspec.json
    codedeploy-application: ${{ env.CODEDEPLOY_APPLICATION }}
    codedeploy-deployment-group: ${{ env.CODEDEPLOY_DEPLOYMENT_GROUP }}
```

このステップで以下が自動的に行われる：

1. 新しいタスク定義をECSに登録
2. AppSpecの `<TASK_DEFINITION>` を新しいタスク定義ARNに置換
3. CodeDeployの `CreateDeployment` APIを呼び出してBlue/Greenデプロイを開始
4. `wait-for-service-stability: true` により、デプロイが完了するまでワークフローが待機

---

## ECS方式との違い

`amazon-ecs-deploy-task-definition` アクションを使う前提では、通常のECS更新との差分はデプロイステップの以下3行になる。

```yaml
codedeploy-appspec: deploy/codedeploy/appspec.json
codedeploy-application: ${{ env.CODEDEPLOY_APPLICATION }}
codedeploy-deployment-group: ${{ env.CODEDEPLOY_DEPLOYMENT_GROUP }}
```

これらのパラメータが指定されると、`amazon-ecs-deploy-task-definition` アクションは通常の `UpdateService` ではなく CodeDeploy の `CreateDeployment` を使う。

ただし、現在のリポジトリの本線は `amazon-ecs-deploy-task-definition` ではなく `ecspresso-update-task.yml` であり、web サービスは ECS ネイティブ Blue/Green を使っている。

---

## 前提条件

CodeDeploy方式を使用するには、AWS側で以下のリソースが事前に作成されている必要がある。

- ECSサービスの `deploymentController` が `CODE_DEPLOY` に設定されていること
- CodeDeployアプリケーションとデプロイメントグループが作成されていること
- ALBに本番用リスナーとテスト用リスナーが設定されていること
- 2つのターゲットグループ（Blue用・Green用）が作成されていること
- GitHub ActionsのOIDCロールにCodeDeploy関連の権限があること（次節参照）

---

## IAMロールの権限

### Rolling Update方式との共通点

ECSのタスク定義登録やサービス更新で使うIAMロールを流用できる。ただし、CodeDeploy関連の権限を追加する必要がある。

### 追加が必要な権限

既存のECS/ECR関連の権限に加えて、以下のCodeDeploy関連の権限を追加する。

```json
{
  "Effect": "Allow",
  "Action": [
    "codedeploy:CreateDeployment",
    "codedeploy:GetDeployment",
    "codedeploy:GetDeploymentConfig",
    "codedeploy:RegisterApplicationRevision",
    "codedeploy:GetApplication"
  ],
  "Resource": [
    "arn:aws:codedeploy:ap-northeast-1:<アカウントID>:application:<CodeDeployアプリケーション名>",
    "arn:aws:codedeploy:ap-northeast-1:<アカウントID>:deploymentgroup:<CodeDeployアプリケーション名>/<デプロイメントグループ名>",
    "arn:aws:codedeploy:ap-northeast-1:<アカウントID>:deploymentconfig:*"
  ]
}
```

### 各アクションの用途

| アクション | 用途 |
|---|---|
| `CreateDeployment` | Blue/Greenデプロイを開始する |
| `GetDeployment` | デプロイ完了を監視する |
| `GetDeploymentConfig` | デプロイ設定（カナリア、線形、AllAtOnce等）を取得する |
| `RegisterApplicationRevision` | AppSpecの情報をCodeDeployに登録する |
| `GetApplication` | CodeDeployアプリケーションの情報を取得する |

既存のECS/ECR関連の権限（`ecs:UpdateService`、`ecs:RegisterTaskDefinition`、`ecs:DescribeServices` 等）はそのまま必要。1つのIAMロールにCodeDeploy権限を追加すれば、ECS方式とCodeDeploy方式の両方に対応できる。

### AWS管理ポリシーについて

カスタムポリシーの代わりにAWS管理ポリシーを使う選択肢もあるが、注意が必要。

- **`AWSCodeDeployRoleForECS`**: CodeDeployの**サービスロール**用のポリシーであり、GitHub ActionsのOIDCロールに付与するものとしては適切ではない（後述）
- **`AWSCodeDeployFullAccess`**: GitHub Actionsから呼び出す側に使えるが、全リソースへのCodeDeploy操作が許可されるため**権限が広すぎる**

#### AWSCodeDeployRoleForECSが適切でない理由

ECSでCodeDeploy方式のBlue/Greenデプロイを行う場合、**2つの異なるIAMロール**が関わる。

| | CodeDeployサービスロール | GitHub ActionsのOIDCロール |
|---|---|---|
| **誰が使うか** | AWS CodeDeployサービス自体 | GitHub Actionsのワークフロー |
| **何をするか** | デプロイ中にECSタスクの起動・停止、ALBのターゲットグループ切替などを実行 | `CreateDeployment` APIを呼んでCodeDeployにデプロイの**開始を指示する** |
| **適切なポリシー** | `AWSCodeDeployRoleForECS` | カスタムポリシー（または `AWSCodeDeployFullAccess`） |
| **信頼ポリシーの対象** | `codedeploy.amazonaws.com` | `token.actions.githubusercontent.com` |

`AWSCodeDeployRoleForECS` にはCodeDeployが裏側でECSやALBを操作するための権限（`ecs:UpdateServicePrimaryTaskSet`、`elasticloadbalancing:ModifyListener` など）が含まれているが、GitHub Actionsから呼ぶ `codedeploy:CreateDeployment` のような権限は含まれていない。役割が異なるため、GitHub ActionsのOIDCロールに `AWSCodeDeployRoleForECS` を付けても必要な権限が得られない。

#### カスタムポリシーとAWS管理ポリシーの比較

| 方法 | メリット | デメリット |
|---|---|---|
| `AWSCodeDeployFullAccess` | 管理ポリシーを付けるだけで簡単 | 全CodeDeployリソースへのフルアクセスになる |
| カスタムポリシー（上記の例） | 必要最小限の権限に絞れる | 自分でポリシーを作成・管理する手間がある |

検証環境や学習用途であれば `AWSCodeDeployFullAccess` を付けても問題ないが、本番環境では最小権限の原則に従い、カスタムポリシーのほうが望ましい。
