> 関連：[../deploy/pr-preview-environment.md](../deploy/pr-preview-environment.md)（PR ごとの検証環境の全体設計）。本書はその中の **「state をどう PR ごとに分けるか」** という一点を深掘りし、採用しなかった選択肢（Terraform workspace）も含めて解説する。
>
> 📌 **前提**：このプロジェクトは preview 環境の state 分離に **backend キーの差し替え方式**を採用しており、**Terraform workspace は使っていません**。本書は「workspace とは何か」「使えばどうなるか」「なぜ使わなかったか」を、仕組みから理解するための教育目的のノートです。

# Terraform Workspace とは / なぜ preview で使わなかったか

## ① 結論（先に答え）

- **workspace でも PR ごとの検証環境は作れる。** 目的（PR ごとに state を分離する）は backend キー方式と同じで、実現手段が違うだけ。
- それでもこのリポは **backend キー方式**（`-backend-config` で state の `key` を PR ごとに差し替える）を選んだ。
- 理由はただ一つ、**「CI での選択ミス事故」を避けるため**。workspace は「今どの workspace にいるか」を CLI が暗黙に握るため、選択を誤ると**間違った環境に `apply` / `destroy`** してしまう危険がある。backend キー方式は対象を毎回コマンドに明示するので、その事故が構造的に起きない。
- トレードオフ：backend キー方式は記述が冗長（partial 設定 + init での key 注入が必要）。workspace は手数が少ない代わりに暗黙状態の事故リスクを抱える。**安全性を取って冗長さを払った**、という判断。

---

## ② Terraform Workspace とは

Terraform 標準の機能で、**同じコード・同じ backend から、複数の独立した state を名前で切り替えて持つ**仕組み。

- 最初は `default` という workspace が1つだけ存在する。`terraform workspace new <名前>` で増やせる。
- **S3 backend の場合、state の保存先パスが workspace ごとに自動で枝分かれする**：

  | workspace | state の置き場所 |
  |---|---|
  | `default` | `<key>` そのまま |
  | `default` 以外（例 `pr-12`） | `env:/pr-12/<key>` という prefix が自動付与 |

- コード内で `terraform.workspace` という値が使え、`name = "app-${terraform.workspace}"` のようにリソース名を workspace ごとに変えられる。
- CLI が「**現在の workspace**」という状態を握る。`terraform workspace select <名前>` で切り替え、`terraform workspace list` で一覧。

ひとことで言うと「**backend は1つのまま、state だけ名前で多重化する**」軽量な仕組み。

---

## ③ workspace で PR ごと環境を作るとしたら

実現は可能。ワークフローはこうなる（あくまで「もし採用していたら」の仮の姿）：

```bash
# 作成（preview-create 相当）
terraform init                          # backend は固定。key の差し替えは不要
terraform workspace new pr-${PR_NUMBER} # or: workspace select pr-${PR_NUMBER}
terraform apply -var="pr_number=${PR_NUMBER}" ...

# 破棄（preview-destroy 相当）
terraform workspace select pr-${PR_NUMBER}
terraform destroy ...
terraform workspace delete pr-${PR_NUMBER}
```

state は `env:/pr-12/...` のように workspace 名で自動分離されるので、PR 同士は干渉しない。

---

## ④ backend キー方式（採用）との比較

このリポの実装は、`terraform/pr-env/providers.tf` の **partial backend 設定**と、workflow 側の init で key を注入する形になっている。

```hcl
# terraform/pr-env/providers.tf
backend "s3" {}   # 空 = partial 設定。詳細は init で渡す
```

```bash
# .github/workflows/preview-create.yml の init
terraform init -input=false \
  -backend-config=pr-env.tfbackend \                                                # 静的部分（bucket/region）
  -backend-config="key=practice/laravel/preview/pr-${PR_NUMBER}/terraform.tfstate"  # 動的部分（PR ごとの key）
```

| 観点 | backend キー方式（採用） | workspace 方式（不採用） |
|---|---|---|
| state の分離 | `key=.../pr-<n>/...` を init で注入 | `env:/pr-<n>/` が自動付与 |
| **対象の指定** | **init コマンドに毎回明示**（key がコマンドに現れる） | CLI の「現在の workspace」に**暗黙依存** |
| 事故りやすさ | 低い（対象が常にコマンドに出る・監査しやすい） | **高い**（select 忘れ・前の選択残りで誤操作） |
| コード量 | 多い（partial 設定 + key 注入が必要） | 少ない（init だけで済む） |
| 命名の分岐 | `var.pr_number` などで明示的に組む | `terraform.workspace` で簡潔に書ける |

---

## ⑤ なぜ workspace を使わなかったか（核心）

`docs/deploy/pr-preview-environment.md` に一行で記録されている方針がこれ：

> workspace は使わない（**CI での選択ミス事故を避ける**）

理由を分解すると：

1. **workspace は「現在地」が暗黙のグローバル状態**。`terraform workspace select` の結果は CLI が握っていて、コマンドの見た目に出てこない。CI のステップで select を書き忘れる、あるいは前のステップの選択が残っていると、**意図と違う workspace に対して `apply` / `destroy` が走る**。最悪、`default`（= 共有 state）を壊しかねない（具体メカニズムは下記）。
2. **HashiCorp 自身が「環境間の強い分離（特に prod）に workspace を使うのは非推奨」**としている。workspace は本来「短命・軽量な差分」向けの機能。
3. backend キー方式なら、**どの state を触るかが `init` のたびにコマンドへ明示**される。レビューでもログでも対象が一目で分かり、誤爆しにくい。

代わりに払うコスト（partial 設定・key 注入のボイラープレート）は受け入れた。**「冗長さ < 誤って別環境を壊さない安全性」** という重み付け。

### 「現在地を暗黙に握る」とは具体的に何か

選択中の workspace 名は、コマンド引数ではなく **作業ディレクトリ内のファイル `.terraform/environment` に書き込まれ、以後のコマンドがそれを黙って読む**。これが「暗黙の現在地」の正体。

```bash
terraform workspace select pr-12
#  → .terraform/environment というファイルに "pr-12" と書かれる

terraform destroy
#  → コマンドに pr-12 とは一切書いていないが、
#    Terraform は .terraform/environment を読んで「pr-12 を destroy」する
```

ポイントは、`terraform destroy` の**コマンドの見た目に対象が現れない**こと。対象は「現在の workspace」という暗黙のグローバル状態で決まる。

**CI での事故シナリオ**：

```bash
terraform init
#  → 新しい runner なので .terraform/environment は無く、workspace は default に戻っている

# ここで「terraform workspace select pr-12」を書き忘れた！

terraform destroy -auto-approve
#  → 現在の workspace = default を destroy
#  → default が stg や共有環境だったら、本番相当を吹き飛ばす
```

`destroy` のコマンド自体は正しく見えるのに、暗黙の現在地が違うせいで別環境を壊す。ログにも `destroy` の文字しか残らず、対象が分からないので気づきにくい。

対して backend キー方式は、対象が**毎回 `init` のコマンドに明示**される：

```bash
terraform init -backend-config="key=practice/laravel/preview/pr-12/terraform.tfstate"
terraform destroy
#  → どの state を触るかが key としてコマンド/ログに残る。誤爆に気づける・監査できる
```

> 補足1（緩和策）：workspace でも `TF_WORKSPACE=pr-12` という環境変数で明示すれば暗黙性をある程度潰せる（select 不要になり、ズレた現在地も上書きされる）。ただし backend-key 方式の「key がコマンドに出る」明示性の方が素直なので、このリポはそちらを選んでいる。
>
> 補足2（workspace の利点）：workspace にも利点はある —— key 差し替えが不要で手数が少なく、`terraform.workspace` で命名を簡潔にできる。小規模・低リスクなら workspace の方が早い。今回は「PR 自動発火 × 多数同時 × 壊れると痛い」という条件下で安全性を優先した、という文脈依存の判断である点に注意。

---

## ⑥ よくある誤解：workspace にすれば output は要らない？

「stg のリソースを pr-env から参照するのに、workspace を使えば `output` を書かなくて済むのでは？」とよく思われるが、**答えは No**。

理由は、**workspace は state を共有しないから**。むしろ逆で、workspace ごとに**完全に独立した state**を持つ。

- workspace `default`（stg とする）で作った `aws_lb.main` は、workspace `pr-12` から見ると**自分の state に存在しない**。`pr-12` で操作している間、Terraform が知っているのは `pr-12` の state だけ。
- だから「別 workspace のリソースをコード内で直接参照する」ことは原理的にできない。

state をまたいで参照する手段は、workspace を使おうが使うまいが結局この2つしかない：

1. **`terraform_remote_state`**（このリポが採用）
   - 他の state を読むが、**読めるのは output として宣言した値だけ**。だから output は必須。
   - workspace 版でも同じで、`workspace` 引数で「どの workspace の state を読むか」を選べるだけ。output を書かなくて済むわけではない。

   ```hcl
   data "terraform_remote_state" "stg" {
     backend   = "s3"
     config    = { bucket = "...", key = "...stg/terraform.tfstate" }
     workspace = "default" # workspace 版でもこれが増えるだけ。output は依然必要
   }
   ```

2. **`data` ソースでの実リソース参照**（AWS API に名前/タグで問い合わせ）
   - 例：`data "aws_lb" "main" { name = "..." }`。AWS 上の既存リソースを直接引くので output 不要。
   - ただしこれは **workspace とは無関係な独立した手段**で、backend-key 方式でも使える。output を減らしたいなら「workspace にする」ではなく「data ソースに置き換える」が正しい打ち手。

さらにこのリポでは、**stg と pr-env はそもそも別ルートモジュール**（別ディレクトリ・別 backend）。workspace は「1つのルートモジュール内で state を多重化する」機能なので、**別モジュール間の参照問題には最初から効かない**。

> 要点：output（または data ソース）が要るのは「**state をまたいで参照するから**」であって、「backend-key 方式だから」ではない。workspace にしても state はまたぐので、output は消えない。

---

## ⑦ 参考記事（日本語）

- **workspace を CLI で使う例**：[GitHub Actions + AWS CodeBuild で PR ごとの検証環境を作ってみた（Zenn）](https://zenn.dev/takenokogohan/articles/574c16cd3aad03) — `terraform workspace new pr123` で PR 番号ベースの workspace を動的生成。マージ/クローズで `destroy` → `workspace delete`。VPC 内 Aurora 接続のため実行基盤は CodeBuild。
- **Terraform Cloud の workspace 変数 + `for_each` の変則例**：[ブランチごとに ECS プレビュー環境を自動生成！Terraform×GitHub Actions（LCL）](https://techblog.lclco.com/entry/2025/03/11/084903) — CLI workspace ではなく、単一 workspace 内の配列変数を API 更新して `for_each` で増減。
- **このリポと同じ backend-key 方式の例**：[PR ごとに検証環境が立ち上がる仕組みを Terraform × GitHub Actions で作った話（エムスリー）](https://www.m3tech.blog/entry/2026/06/16/153849) — S3 backend の key を PR 番号で動的に組み立てて init。本リポと同思想。
- **workspace の使いどころへの言及**：[第5回:Terraform と GitHub Actions で構築するインフラ CD（CADDi）](https://caddi.tech/archives/4427)
