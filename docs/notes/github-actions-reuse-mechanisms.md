> 関連：[../adr/0010-terraform-plan-summary-without-ai.md](../adr/0010-terraform-plan-summary-without-ai.md)（この部品を作った設計判断）、実装した本体 [`.github/actions/tf-plan-summary/action.yml`](../../.github/actions/tf-plan-summary/action.yml) と、それを呼ぶ [`.github/workflows/terraform-apply-plan.yml`](../../.github/workflows/terraform-apply-plan.yml) / [`.github/workflows/preview-create.yml`](../../.github/workflows/preview-create.yml)。
>
> 📌 **前提**：このプロジェクトは Terraform のプラン要約処理を **Composite Action** として `.github/actions/tf-plan-summary/` に切り出し、2本のワークフローから `uses:` で共有しています。本書は「GitHub Actions の処理を再利用・部品化する方法」を全体地図として整理し、**なぜ今回 Composite Action を選んだのか**を、採用しなかった選択肢（JavaScript / Docker action / Reusable Workflow）も含めて仕組みから理解するための教育ノートです。

# GitHub Actions の再利用の仕組み（Composite / JavaScript / Docker Action と Reusable Workflow）

## ① 結論（先に答え）

- GitHub Actions の「部品化」は、まず **2つの階層**に分かれる。**Action（＝再利用できる "ステップ"）** と **Reusable Workflow（＝再利用できる "ジョブ群＝ワークフロー丸ごと"）**。ここを混同すると比較がボヤける。
- さらに **Action には3種類**ある：**① Composite**（シェルや既存 action を束ねる）、**② JavaScript**（JS を runner 上で直接実行）、**③ Docker**（コンテナの中で実行）。今回使ったのは **① Composite**。
- **一番大事な違い**は「**呼び出し元と同じジョブ（同じ runner）で動くか、別ジョブ（別 runner）として動くか**」。Action は**呼び出し元のジョブの中**でステップとして動く。Reusable Workflow は**独立した別ジョブ**として動く。
- 今回 `tf-plan-summary` を **Composite Action** にしたのは、この処理が「`terraform plan` で作った `tfplan` ファイルを、**同じジョブの・同じディスク上**で読み、`terraform apply` の**直前のステップ**として差し込む」ものだから。別 runner で動く Reusable Workflow では `tfplan` が手元に無く、この置き場所も作れない（後述⑦）。
- ざっくりの使い分け：**1ジョブ内の数ステップを共有したい → Action（普通は Composite）。ジョブ構成ごと（ビルド→テスト→デプロイ等）を共有したい → Reusable Workflow。**

---

## ② 大前提：GitHub Actions の用語を3秒で整理

部品化を理解する前に、GitHub Actions の入れ子構造を押さえます。大きい方から：

```
Workflow（ワークフロー）   .github/workflows/*.yml の1ファイル。「いつ動くか(on:)」を持つ
  └─ Job（ジョブ）          独立した runner（仮想マシン）1台の上で動く処理のかたまり
       └─ Step（ステップ）  上から順に実行される1コマンド。run: か uses: のどちらか
            └─ Action       uses: で呼ぶ「再利用可能なステップの部品」
```

- **Workflow** … 「PR が来たら」「手動で」など**起動条件（`on:`）**を持つ一番外側の単位。
- **Job** … それぞれ**まっさらな別マシン（runner）**で動く。ジョブが違えばディスクもメモリも別。だからジョブ間でファイルを渡すには artifact のアップロード/ダウンロードが要る。
- **Step** … ジョブの中で**上から順番**に走る。`run:`（シェルコマンド）か `uses:`（action の呼び出し）。**同じジョブのステップ同士は同じディスク・同じ環境変数を共有する**。
- **Action** … `uses:` で呼ぶステップの部品。Marketplace の `actions/checkout@v4` もこれ。

ここで再利用の仕組みは、**この階層の「どこ」を部品にするか**で分かれます。

| 部品化するもの | 仕組みの名前 | ひとことで |
|---|---|---|
| **ステップ（の集まり）** | **Action**（Composite / JS / Docker の3種） | 「このステップ列、使い回したい」 |
| **ジョブ群（＝ワークフロー丸ごと）** | **Reusable Workflow** | 「このジョブ構成ごと、使い回したい」 |

> 🔑 **ここが核心**：Action は「**ステップ**の部品」。Reusable Workflow は「**ジョブ（ワークフロー）**の部品」。階層が一段違います。

---

## ③ Action の3種類 — Composite / JavaScript / Docker

「Action」と一口に言っても、**中身を何で書くか**で3種類あります。どれも `action.yml`（または `action.yaml`）という定義ファイルを持ち、`inputs:` / `outputs:` を宣言できる点は共通で、違うのは `runs:` の中身です。

### ③-1 Composite Action（今回採用）

**複数のステップ（シェルや既存 action）を1つの action.yml に束ねる**タイプ。中身は基本的に**シェルスクリプトの集まり**。

```yaml
runs:
  using: composite      # ← これが Composite の目印
  steps:
    - shell: bash        # ← run: ステップには shell の明示が必須（後述の落とし穴）
      run: echo "hello"
    - uses: actions/setup-node@v4   # 既存 action を中に入れることもできる
```

- **得意**：runner にすでにある道具（bash, jq, terraform, aws-cli …）を組み合わせる「手順のかたまり」をまとめる。
- **コスト**：ほぼゼロ。コンテナのビルドも JS の依存インストールも要らず、ただ手順を展開して走らせるだけ。

### ③-2 JavaScript Action

**JavaScript（Node.js）のファイルを runner 上で直接実行**するタイプ。

```yaml
runs:
  using: node20         # Node のランタイムで
  main: dist/index.js   # この JS を実行する
```

- **得意**：複雑なロジック、JSON/API の本格的な加工、Windows/macOS/Linux **どの OS の runner でも同じに動く**こと（Docker action は Linux 専用なのが弱点）。`@actions/core` などの公式ツールキットで入出力やログを扱える。`actions/checkout` や `actions/github-script` もこの仲間。
- **コスト**：JS を書く＆ビルド（依存を1ファイルにまとめる）手間がかかる。シェル数行で済む処理には過剰。

### ③-3 Docker Container Action

**Dockerfile（またはビルド済みイメージ）からコンテナを起動し、その中で処理を実行**するタイプ。

```yaml
runs:
  using: docker
  image: Dockerfile     # or "docker://ghcr.io/...":ビルド済みイメージ
```

- **得意**：runner に無い特殊なツールや特定バージョンの言語環境を**コンテナに同梱**して、環境差を完全に固定したいとき。
- **コスト**：毎回イメージのビルド or pull が走るので**起動が遅い**。そして **Linux runner でしか動かない**（このプロジェクトの runner は `ubuntu-latest` なのでそこは問題ないが、汎用部品としては制約）。

### 3種の早見表

| | Composite | JavaScript | Docker |
|---|---|---|---|
| 中身 | シェル＋既存action | Node.js コード | コンテナ（任意の言語/ツール） |
| 起動の速さ | 速い（展開するだけ） | 速い | 遅い（build/pull） |
| OS | runner 依存（bash 前提など） | クロスプラットフォーム◎ | **Linux 専用** |
| 向く用途 | 既存ツールの手順をまとめる | 複雑なロジック・API加工 | 特殊ツールを同梱したい |
| 学習コスト | 低 | 中（JS＋ビルド） | 中（Dockerfile） |

> 今回の `tf-plan-summary` は「runner にある `terraform` と `jq` でプランを整形し Summary に書く」という**まさにシェル手順の塊**。だから Composite が素直にハマります（③-1 の "得意" そのもの）。

---

## ④ Composite Action 深掘り — `tf-plan-summary` を読む

実際に作った部品を題材に、Composite Action の骨格を見ます。場所は [`.github/actions/tf-plan-summary/action.yml`](../../.github/actions/tf-plan-summary/action.yml)。

### (1) 入口の宣言：`name` / `inputs`

```yaml
name: "Terraform Plan Summary"            # action.yml:8
inputs:                                   # action.yml:11
  plan-file:        { required: true }    # 保存したプランファイル名（例: tfplan）
  working-directory:{ required: true }    # plan を保存したディレクトリ
  title:            { required: true }    # Summary の見出しラベル
```

`inputs:` は、この部品を**外から調整するためのつまみ**です。呼び出し側が `with:` で値を渡し、action 内では `${{ inputs.plan-file }}` のように参照します。関数の引数だと思えば近いです。

### (2) 本体：`runs.using: composite`

```yaml
runs:
  using: composite                              # action.yml:23 ← Composite の宣言
  steps:
    - shell: bash                               # ← shell の明示が必須
      working-directory: ${{ inputs.working-directory }}   # action.yml:26
      env:
        PLAN_FILE: ${{ inputs.plan-file }}
        TITLE: ${{ inputs.title }}
      run: |
        set -euo pipefail
        terraform show -json "$PLAN_FILE" > plan.json   # プランをJSON化
        # jq で create/update/delete/replace に分類して $GITHUB_STEP_SUMMARY へ
        ...
```

ポイントは3つ：

1. **`using: composite`** がこの action を「ステップの束」として扱う宣言。
2. **`shell: bash` が必須**。通常のワークフローの `run:` はデフォルトシェルが効きますが、**Composite Action の中の `run:` はシェルを必ず明示**しないとエラーになります（落とし穴⑨で再掲）。
3. **`inputs` を `env:` 経由で受け取っている**。`${{ inputs.x }}` を `run:` の本文に直接埋めると、値に変な文字が混じったときシェルとして壊れる/危険なので、いったん環境変数に渡してから `"$PLAN_FILE"` と参照する、という安全な作法です。

### (3) 呼び出し側：たった数行

呼ぶ側（[`terraform-apply-plan.yml:107`](../../.github/workflows/terraform-apply-plan.yml)）はこうです：

```yaml
- name: Summarize plan
  uses: ./.github/actions/tf-plan-summary   # ← ローカルパスで呼ぶ
  with:
    plan-file: tfplan
    working-directory: ./terraform/${{ inputs.target_env }}
    title: ${{ inputs.target_env }}
```

`uses: ./.github/actions/...` の**先頭の `./`** が「**このリポジトリ内のローカル action**」という意味です（Marketplace の `actions/checkout@v4` のような `owner/repo` 形式ではなく）。`preview-create.yml:136` でも全く同じ部品を `working-directory: ./terraform/pr-env` で呼んでいて、**1つの部品を2本のワークフローが共有**できています。これが「部品化」の果実です。

> ⚠️ ローカル action を `uses:` する前には、ジョブで **`actions/checkout` が済んでいる**必要があります（action のファイルがディスク上に無いと呼べないため）。両ワークフローとも先頭で checkout 済みなのでOK。

---

## ⑤ Reusable Workflow とは — `workflow_call`

もう一方の柱、Reusable Workflow です。これは**ワークフロー（ジョブ群）丸ごと**を部品にします。

### 呼ばれる側（部品ワークフロー）

```yaml
# .github/workflows/deploy.yml（部品側）
on:
  workflow_call:           # ← これが「他から呼ばれる用」の宣言
    inputs:
      environment:
        type: string
        required: true
    secrets:
      token:
        required: true
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: echo "deploy to ${{ inputs.environment }}"
```

### 呼ぶ側

```yaml
jobs:
  call-deploy:
    uses: ./.github/workflows/deploy.yml   # ← steps: の中ではなく job レベルで uses:
    with:
      environment: stg
    secrets:
      token: ${{ secrets.DEPLOY_TOKEN }}
```

注目してほしいのは **`uses:` を書く場所**です。Action は `steps:` の中（ステップとして）呼びましたが、Reusable Workflow は **`jobs.<id>.uses:`（ジョブとして）** 呼びます。**呼んだ側ではその下に `steps:` を書けません**——丸ごと別ワークフローに委ねるからです。

そして決定的なのは、**呼ばれた Reusable Workflow は独立した別ジョブ（別 runner）として動く**こと。呼び出し元のジョブが持っていたファイルや環境変数は**引き継がれません**。

---

## ⑥ Composite Action vs Reusable Workflow ── 比較表

「結局どっちを使えばいいの？」に効く軸で並べます。

| 比較軸 | **Composite Action** | **Reusable Workflow** |
|---|---|---|
| 再利用の単位 | **ステップ群** | **ジョブ群（ワークフロー丸ごと）** |
| 呼び出し方 | `steps:` 内で `- uses:` | `jobs.<id>.uses:`（ジョブ位置） |
| **実行環境** | **呼び出し元と同じジョブ・同じ runner** | **独立した別ジョブ・別 runner** |
| ファイル共有 | 呼び出し元のディスクをそのまま使える | 別マシンなので artifact 等で受け渡しが必要 |
| 既に入った道具/checkout | **呼び出し元のものをそのまま使える** | 別runnerなので**自前で再 checkout / 再 setup** |
| secrets の渡し方 | 自動では渡らない。`with`/`env` で明示 | `secrets:` ブロック、または `secrets: inherit` |
| matrix / needs / if / environment | **使えない**（ステップなので） | **使える**（ジョブだから） |
| ジョブの並列・依存関係 | 表現できない | `needs:` で複数ジョブを編成できる |
| ログの見え方 | 呼び出し元ジョブに**展開**して並ぶ | **別ジョブ**として折りたたまれる |
| outputs | `outputs:` でステップ出力を集約 | `jobs.<id>.outputs` 経由 |
| ネスト上限 | action は action を呼べる | Reusable は**4段まで** |
| 向く粒度 | 「1ジョブ内の数ステップ」 | 「ジョブ構成ごと（build→test→deploy）」 |

> 🔑 表の中で太字にした **「実行環境（同じジョブ／別ジョブ）」** が、ほぼ全ての違いの根っこです。ファイル共有・secrets・matrix・ログの違いは、すべて「同じ runner にいるか／別 runner か」から派生しています。

---

## ⑦ このプロジェクトはなぜ Composite を選んだか

`tf-plan-summary` の仕事を思い出します（[ADR 0010](../adr/0010-terraform-plan-summary-without-ai.md)）。ワークフローは3段構成でした：

```
① terraform plan -out=tfplan   ← tfplan ファイルを作る
② Summarize plan               ← ★ここに差し込む。tfplan を読んで Summary を書く
③ terraform apply tfplan       ← 同じ tfplan を適用
```

②の処理には、こういう要求があります：

1. **①が作った `tfplan` ファイルを読む** → ①と**同じディスク**にいる必要がある。
2. **②が失敗したら③をスキップしたい（フェイルクローズ）** → ②は①と③の**間のステップ**として、**同じジョブの中**に並んでいる必要がある。
3. ①の時点で **`terraform` も AWS 認証も済んでいる** → それを**そのまま使いたい**。

この3つは全部「**①②③が同じジョブ・同じ runner にいる**」ことが前提です。**Composite Action はまさに呼び出し元のジョブの中でステップとして動く**ので、3つとも自然に満たせます。

では Reusable Workflow にしたら？ ②が**別ジョブ（別 runner）**になります。すると：

- `tfplan` が**手元に無い**（別マシン）。①のジョブで artifact にアップロードし、②のジョブでダウンロードする配線が要る。
- `terraform` も AWS 認証も**まっさら**。②のジョブで再 setup・再認証が要る。
- そもそも「①と③の**間**に挟まる」という置き方が**ジョブの世界では作れない**（②が別ジョブになると③との順序は `needs:` で組むことになり、"applyの直前のステップ" という関係が崩れる）。

つまり Reusable Workflow は**この仕事には構造的に合いません**。「数ステップを同じジョブ内で共有したい」のだから Composite が正解、というわけです。表⑥の「実行環境」の行が、そのまま決め手になっています。

> 逆に Reusable Workflow が輝くのは、例えば「stg と prod で **`init → plan → apply` というジョブ構成ごと**同じにしたい」ような場面です。そこではジョブ単位の再利用が効きます。今回は粒度が「ジョブ内の1ステップ」なので、階層が一段違いました。

---

## ⑧ 同じ `tf-plan-summary` を3方式で書き分けると（理解用の対比）

「もし別の方式で作っていたら」を並べると、違いが体で分かります。**やることは同じ**（プランを読んで Summary に整形して出す）。

### (a) Composite Action（実際の採用形）

```yaml
runs:
  using: composite
  steps:
    - shell: bash
      run: |
        terraform show -json "$PLAN_FILE" > plan.json
        jq -r '...' plan.json | ... >> "$GITHUB_STEP_SUMMARY"
```
- 同じジョブで動くので `tfplan` も `terraform` もそのまま使える。**今回のベストフィット**。

### (b) JavaScript Action だったら

```yaml
runs:
  using: node20
  main: dist/index.js
```
```js
// index.js（イメージ）
const core = require('@actions/core');
const { execSync } = require('child_process');
const planFile = core.getInput('plan-file');
const json = JSON.parse(execSync(`terraform show -json ${planFile}`).toString());
const md = buildMarkdown(json.resource_changes);   // jq の代わりに JS で集計
require('fs').appendFileSync(process.env.GITHUB_STEP_SUMMARY, md);
```
- **置き場所は (a) と同じ**（同じジョブのステップ）。違いは「集計ロジックを `jq` ではなく JS で書く」点だけ。
- **嬉しいのは**：分類ロジックが複雑になったり、ユニットテストを書きたくなったとき。Windows runner でも動く。
- **今回は過剰**：`jq` 数行で済むのに JS のビルド環境（`node_modules` を1ファイルに束ねる作業）を背負うことになる。

### (c) Docker Action だったら

```yaml
runs:
  using: docker
  image: Dockerfile     # jq や terraform を焼き込んだイメージ
```
- これも**置き場所は (a) と同じ**ステップ。違いは「処理がコンテナの中で走る」点。
- **嬉しいのは**：runner に無い特殊バージョンのツールを固定したいとき。
- **今回は過剰＆遅い**：必要な道具（terraform/jq）は runner にもう在る。毎回イメージを build/pull する分だけ遅くなり、Linux 専用の制約も付く。

### (d) Reusable Workflow だったら（構造が変わる）

```yaml
# 呼ぶ側は steps ではなく job として
jobs:
  summarize:
    uses: ./.github/workflows/tf-summary.yml
    with: { plan-file: tfplan }
```
- ここだけ**形が根本的に違う**。②が**別ジョブ**になり、`tfplan` を artifact で受け渡し、terraform を再 setup…と配線が増える。しかも「applyの直前」という置き場所が作れない（⑦）。
- **この仕事には不適**。Reusable Workflow は「ジョブ構成ごと再利用」のための道具。

> 並べると分かるのは、**(a)(b)(c) は "同じ場所に置ける仲間"（＝Action の3種）**で、選択は「**中身を何で書くか**」の違いにすぎないこと。一方 **(d) だけが階層の違う別物**で、置き場所そのものが変わること。⑥の表の「再利用の単位」がここに効いています。

---

## ⑨ 落とし穴・注意点

- **Composite の `run:` には `shell:` 必須**。通常ワークフローと違いデフォルトシェルが無く、書き忘れるとエラー。今回は `shell: bash`（action.yml:25 付近）。
- **ローカル action は checkout 後でないと呼べない**。`uses: ./.github/actions/...` はディスク上のファイルを読むので、先に `actions/checkout` が要る。
- **`inputs` を `run:` 本文に直接埋め込まない**。`${{ inputs.x }}` を本文に直書きすると、値次第でシェルが壊れる/インジェクションの恐れ。いったん `env:` に渡して `"$VAR"` で使うのが安全（今回そうしている）。
- **Composite の `working-directory`**。Composite 内の `run:` ステップは、呼び出し元ジョブの `defaults.run.working-directory` を**自動では継がない**。今回は `inputs.working-directory` を明示的に受け取って各ステップに指定している（action.yml:26）。
- **Composite では secrets が自動で来ない**。必要なら呼び出し側で `with:` か `env:` に渡す。Reusable Workflow の `secrets: inherit` のような一括継承は無い。
- **Reusable Workflow のネストは4段まで**、呼び出しは job レベル（`jobs.<id>.uses:`）でのみ。`steps:` の中には書けない。
- **バージョン固定**：他リポの action/Reusable Workflow を使うときは `@v4` や `@<commit-sha>` で固定する。`@main` 参照は供給側の変更で突然壊れる/サプライチェーンのリスク。ローカル action（`./...`）は同じリポなのでこの心配は無い。

---

## 用語集

- **Workflow** — `.github/workflows/*.yml` の1ファイル。起動条件（`on:`）を持つ最外側の単位。
- **Job（ジョブ）** — 独立した runner（仮想マシン）1台で動く処理のかたまり。ジョブが違えばディスク・環境は別。
- **Step（ステップ）** — ジョブ内で上から順に走る1コマンド。`run:` か `uses:`。同一ジョブのステップはディスク・環境変数を共有。
- **Action** — `uses:` で呼ぶ「再利用可能なステップの部品」。中身の作り方で Composite / JavaScript / Docker の3種。
- **Composite Action** — 複数ステップ（シェル＋既存action）を1つに束ねた action。`runs.using: composite`。
- **Reusable Workflow** — ワークフロー（ジョブ群）丸ごとを部品化したもの。`on: workflow_call` で定義し `jobs.<id>.uses:` で呼ぶ。
- **runner** — ジョブを実際に実行する仮想マシン。GitHub ホスト（`ubuntu-latest` 等）かセルフホスト。
- **artifact** — ジョブ間（別 runner 間）でファイルを受け渡すための保存物。アップロード/ダウンロードで使う。
- **`secrets: inherit`** — Reusable Workflow に呼び出し元の secrets を一括で引き継がせる指定。Composite には無い概念。
- **`$GITHUB_STEP_SUMMARY`** — 各ジョブの Summary 欄に Markdown を書き出すための特殊ファイルのパス。

## 関連コード / さらに読む

自力で読む練習に、まずこの3つを突き合わせてみてください：

- [`.github/actions/tf-plan-summary/action.yml`](../../.github/actions/tf-plan-summary/action.yml) — 部品本体（Composite）。
- [`.github/workflows/terraform-apply-plan.yml`](../../.github/workflows/terraform-apply-plan.yml)（107行目付近）と [`.github/workflows/preview-create.yml`](../../.github/workflows/preview-create.yml)（135行目付近）— **同じ部品を2箇所から呼んでいる**様子。
- [ADR 0010](../adr/0010-terraform-plan-summary-without-ai.md) — なぜこの部品が生まれたか（設計判断）。
- 公式ドキュメント：「Creating a composite action」「Reusing workflows」（GitHub Docs）。本書の内容の一次情報。

## 理解度チェッククイズ

考えてみてください（答えはここには書きません。答えを書いてくれたら正誤と補足を返します）：

1. `tf-plan-summary` を Reusable Workflow で作り直したら、`terraform plan` が作った `tfplan` ファイルはなぜ「②の処理から見えなくなる」のでしょうか？ ⑥の表のどの行がその理由ですか？
2. 「Windows・macOS・Linux のどの runner でも同じに動く汎用部品を配りたい」とき、Action の3種（Composite / JavaScript / Docker）のうちどれが一番向いていて、どれが**使えない**でしょうか？ それぞれ理由も。
3. あるチームが「`build → test → deploy` という**ジョブ構成**を、5つのリポジトリで全く同じにしたい」と言っています。Composite Action と Reusable Workflow のどちらを勧めますか？ なぜ？
