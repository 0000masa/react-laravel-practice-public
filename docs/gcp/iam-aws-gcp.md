# GCP IAM の考え方（AWS との比較）

Cloud Run / Cloud SQL / Secret Manager などを手作業で作るとき（[manual-setup-console.md](./manual-setup-console.md)）に
何度もつまずく **GCP IAM のモデル**を、AWS と対比して整理する。実装は本 repo の
`service_account.tf` / `ci.tf` / `cloud_run.tf` に対応。

> 一言でいうと: **GCP の権限は「`principal × role × リソース` のバインディングを、リソース側（か上位階層）に
> 貼る」だけ**でできている。AWS のように「principal 側に identity ポリシーを貼る」概念が無い。
> ここを掴むと残りは全部その応用。

---

## 1. ロールは3種類（基本は「事前定義」を選ぶ）

ロールは自作もできるが、**まず事前定義ロールから選ぶ**のが実務の基本。

| 種類 | 誰が作る | 例 | 使いどころ |
| --- | --- | --- | --- |
| 基本（basic / primitive） | Google（固定） | `Owner` / `Editor` / `Viewer` | 全サービス横断で広すぎる。本番では避ける |
| **事前定義（predefined）** | **Google が作成・保守** | `roles/secretmanager.secretAccessor` | **主役**。まずここから選ぶ。permission 追加に自動追随 |
| カスタム（custom） | 自分で定義 | （任意の permission を束ねる） | 事前定義だと粒度が合わないときの最終手段。保守は自前 |

本 repo は `roles/cloudsql.client` / `roles/secretmanager.secretAccessor` / `roles/storage.objectAdmin` /
`roles/artifactregistry.writer` / `roles/iam.workloadIdentityUser` と、**すべて事前定義ロール**で足りている。

> **AWS 対応**: 事前定義ロール ≈ **AWS マネージドポリシー**、カスタムロール ≈ **カスタマー管理ポリシー**。
> 基本ロール（Owner/Editor/Viewer）に綺麗に対応する AWS 概念は薄い（強いて言えば `AdministratorAccess` 等）。

## 2. ロール＝permission の束（「名前」ではなく「中身」が効く）

ロールの正体は **permission の束**で、各 permission は `サービス.リソース.動詞` の形
（例 `secretmanager.versions.access`、`storage.objects.get`）。

重要な性質:

- **ロール単体では誰にも何も許可しない。** ロールは“定義”にすぎず、**principal にリソース上でバインドして
  初めて効く**（→ 手順 3）。「ロールに権限はあるが足りないので別途リソース側でも許可」という**二重設定ではない**。
  **バインド＝唯一の付与操作**。
- **効くかは「ロールの中身 × 対象リソースの種類」で決まる。名前は単なるラベル。**
  - 例: シークレットの権限タブで `roles/storage.objectAdmin`（中身は `storage.*`）を貼っても、
    シークレット読み取りに必要な `secretmanager.versions.access` を含まないので **何も起きない（no-op）**。
  - 逆に中身に `secretmanager.versions.access` を含むロールなら（名前が何であれ）読める。
- ⚠️ 基本ロール（Owner/Editor）や `*.admin` 系は**中身が広い**ため、上位階層に安易に貼ると効きすぎる。

> **AWS 対応**: 「ポリシー＝permission の集合」「`Action`＝permission」という構造は同じ。GCP の
> `secretmanager.versions.access` は AWS の `secretsmanager:GetSecretValue` に相当する粒度。

## 3. 付与のモデル：`principal × role × リソース` を「リソース側」に貼る

GCP の権限は、リソース（または project / folder / org の上位階層）の **IAM allow ポリシー**に
`{ principal, role }` のバインディングを足すことで与える。**principal（SA など）側にポリシーを貼る概念は無い。**

→ だから **「どのリソースで付与するか」がそのままスコープ**になる。

| 付与する場所 | 効く範囲 | 例（本 repo） |
| --- | --- | --- |
| 個別シークレットの権限タブ | そのシークレットだけ | 実行 SA に `secretAccessor`（4 シークレットに個別付与） |
| バケットの権限タブ | そのバケットだけ | 実行 SA に `storage.objectAdmin`（画像バケットのみ） |
| プロジェクトの IAM 画面 | プロジェクト内の対象リソース全部 | 実行 SA に `cloudsql.client` |

> 同じ `secretAccessor` でも、**プロジェクト**で付ければ全シークレット、**個別シークレット**で付ければ 1 個だけ。
> 最小権限＝「必要 permission を含むロールを、必要なリソースのスコープで貼る」。

### AWS との決定的な違い

| | 権限を貼る場所 | 位置づけ |
| --- | --- | --- |
| **AWS identity-based policy** | IAM ロール/ユーザー（**principal 側**） | 通常はこれで完結。リソース側を触らない |
| **AWS resource-based policy**（S3 バケットポリシー / KMS キーポリシー / Secrets Manager リソースポリシー） | リソース側 | **任意の追加層**（Parameter Store には無い） |
| **GCP IAM allow policy** | **リソース（か上位階層）側のみ** | これが**唯一**の手段。principal 側に貼る選択肢が無い |

- AWS（同一アカウント）は **ロールに identity ポリシーを貼って終わり**が普通。
- GCP は principal 側に貼れないので、**必ずリソース側で付与**。「SA にロールを付与」と「リソース側で許可」は
  **別操作ではなく同じ 1 バインディング**。

## 4. principal（メンバー）の種類

principal = **アクセスを与えられる ID**。バインディングの `member` に書けるもの:

| principal | 例 |
| --- | --- |
| ユーザー | `user:alice@example.com` |
| グループ | `group:admins@example.com` |
| ドメイン | `domain:example.com` |
| サービスアカウント | `serviceAccount:practice-gcp-stg-run@<PROJECT_ID>.iam.gserviceaccount.com` |
| フェデレーション ID（WIF） | `principalSet://…/attribute.repository/0000masa/react-laravel-practice-public` |
| 特殊 | `allUsers` / `allAuthenticatedUsers` |

> **AWS 対応の注意（ポリシー種別と Principal 欄）**: 「AWS の IAM ポリシー」は種別で Principal 欄の有無が違う。
>
> | AWS ポリシー種別 | 何か | 貼る場所 | Principal 欄 |
> | --- | --- | --- | --- |
> | **identity-based policy** | 「この ID が何をしてよいか」を定義（例 `AmazonS3ReadOnlyAccess` / 自作 / インライン）。`Effect`/`Action`/`Resource` を持つ | IAM ユーザー/グループ/ロール | **無い**（principal＝アタッチ先で自明） |
> | resource-based policy | 「誰がこのリソースにアクセス可か」（S3 バケットポリシー等） | リソース | ある |
> | trust policy（信頼ポリシー） | 「誰がこのロールを assume 可か」 | ロール | ある |
>
> AWS で権限を与える基本は **identity-based policy（ID 側に貼る・Principal 欄なし）**。GCP にはこの
> 「ID 側に貼る」手段が無く、**全ての付与がリソース側**なので、**どのバインディングにも必ず principal が並ぶ**。

## 5. サービスアカウントの「2つの顔」＝2枚の IAM ポリシー

SA は **アイデンティティ**であると同時に **リソース**でもある。そのため SA をめぐって
**役割の違う 2 枚の IAM ポリシー**が存在する（混同しやすい最重要ポイント）。

| ポリシー | 貼られる場所 | 決めること | 代表ロール |
| --- | --- | --- | --- |
| **権限側** | 各リソース（Secret / バケット / プロジェクト） | この SA が**何をできるか** | `secretAccessor` / `storage.objectAdmin` / `cloudsql.client` |
| **トラスト側** | **SA 自身**（SA はリソース） | **誰がこの SA を使える/なりすませるか** | `iam.serviceAccountUser`(actAs) / `iam.serviceAccountTokenCreator` / `iam.workloadIdentityUser` |

**トラスト側が AWS の信頼ポリシーに相当**する。ただし縛れる軸が違う:

| | AWS 信頼ポリシー | GCP（SA のトラスト側 IAM） |
| --- | --- | --- |
| **サービス種別で縛る**（ECS だけ / Lambda だけ） | ✅ `Principal: { Service: "ecs-tasks.amazonaws.com" }` | ❌ **書けない**（`service:` という member 型が無い） |
| **ID（principal）で縛る** | ✅ アカウント / ロール / フェデレーション | ✅ `serviceAccount:` / `user:` / `principalSet:`（**リポジトリ単位まで**細かく） |

- 「**principal 単位なら細かく指定できる**」＝**誰（ID）**を名指しで、GitHub の 1 リポジトリまで絞れる。
- 「**サービス単位では指定できない**」＝**どの GCP プロダクトか**（Cloud Run 限定 等）では縛れない。
- なぜ要らないか: GCP は「SA が Cloud Run という種別を信頼する」のではなく、**特定の Cloud Run サービスに
  SA を割り当て**、その**割り当てをできる人を `serviceAccountUser`(actAs) で絞る**ことで制御するから。
  ＝縛る軸が「サービス種別」ではなく「**操作する principal**」に寄っている。

### `serviceAccountUser`(actAs) は「割り当てできる人」を絞る＝権限昇格防止

- 「割り当てをできる人」とは、**「この SA をこのリソースに割り当てて動かそう」と設定する principal**
  （デプロイする開発者や、CI / Terraform が使う SA）のこと。
- 例: 開発者 `alice@` が「Cloud Run を `practice-gcp-stg-run` として動かす」設定でデプロイするには、
  ① Cloud Run のデプロイ権限（`roles/run.developer` 等）と
  ② **その SA への `roles/iam.serviceAccountUser`（actAs）** の両方が要る。②が無いと割り当て時に権限エラー。
- **なぜ必要か（重要）**: actAs が不要なら、弱い権限の alice が**強い権限の SA を自分のサービスに割り当てて
  なりすまし、権限昇格**できてしまう。actAs 必須にすることで「**その SA を使ってよいと認められた人だけ**が
  割り当てできる」ようにしている。

### SA は排他ではない（複数リソースで共有できる）

- 1 つの SA を**複数のリソースに割り当て可能**。Cloud Run に付けてもロックされない。
- SA は**それ自体が principal（ID）**。「SA を principal に付ける」のではなく、「**リソースに SA を割り当てて、
  そのリソースを“その SA として”動かす**」のが正しい捉え方。
- 実例（本 repo）: 同じ `practice-gcp-stg-run` を **Cloud Run サービス**（`cloud_run.tf`）と
  **migrate ジョブ**（`cloud_run_job.tf`）の両方が共有している。

## 6. 本 repo の実例で総点検

### 実行 SA がシークレットを読む（権限側）

1. Cloud Run サービスに実行 SA `practice-gcp-stg-run` を割り当て（`cloud_run.tf` の `service_account`）。
   → Cloud Run は「その SA として」動く。割り当てるには操作者が SA に `actAs` を持つ必要（トラスト側）。
2. 各シークレットの IAM に `{ principal: 実行 SA, role: secretAccessor }` を付与（権限側）。
   → `google_secret_manager_secret_iam_member`（シークレット単位）。
3. 実行時、SA のトークンで読みに行く → シークレット側ポリシーが許可。

### GitHub Actions がデプロイ SA を使う（トラスト側＝AWS 信頼ポリシー相当）

`ci.tf`:

- `google_service_account_iam_member.wif_push`:
  **SA 自身**に `roles/iam.workloadIdentityUser` を、member
  `principalSet://…/attribute.repository/<github_repository>` へ付与
  → 「**このリポジトリの GitHub Actions だけがこの SA をなりすませる**」（トラスト側）。
- `roles/artifactregistry.writer` を **AR リポジトリ**に付与（権限側）。

これは AWS の「GitHub OIDC を信頼し、特定リポジトリだけ role を assume させる」信頼ポリシー＋
権限ポリシーの組に **1:1 で対応**する。

---

## AWS ⇔ GCP 早見表

| 観点 | AWS | GCP |
| --- | --- | --- |
| 権限の束 | マネージド / カスタマー管理ポリシー | 事前定義 / カスタムロール |
| permission | `secretsmanager:GetSecretValue` | `secretmanager.versions.access` |
| 権限を貼る場所 | principal 側（identity ポリシー）が主 | **リソース側（か上位階層）のみ** |
| リソース側ポリシー | 任意の追加層（S3/KMS/Secrets Manager） | これが唯一の手段 |
| 信頼ポリシー（誰が使えるか） | ロールの信頼ポリシー | **SA 自身の IAM ポリシー**（serviceAccountUser 等） |
| サービス種別での信頼 | ✅ `Principal.Service` | ❌ 無い（SA 割り当て＋actAs で代替） |
| フェデレーション（GitHub Actions） | OIDC プロバイダ + 条件 | WIF + `workloadIdentityUser` × `principalSet` |

> 関連: 付与のコンソール操作は [manual-setup-console.md](./manual-setup-console.md) 手順6 / 手順12、
> DB 接続文脈での IAM は [db-connection-aws-gcp.md](./db-connection-aws-gcp.md) を参照。
