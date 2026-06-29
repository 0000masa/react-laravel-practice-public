---
status: accepted
---

# Terraform の変更要約は AI ではなく `terraform show -json` + jq の決定的パースで GitHub Actions Summary に出す

## 背景

`terraform-apply-plan.yml`（手動・stg/prod）と `preview-create.yml`（PR 自動）では Terraform を実行している。何が作成・変更・削除されるかは Terraform のログから追えるが、(1) `terraform plan` の出力は人間が読むには冗長で、(2) GitHub Actions のログはシェルの色付け（差分の +/- 色）が効かず、さらに読みづらい。

そこで「作成・変更されるリソースを GitHub Actions の Summary に分かりやすくまとめたい」という要求が出た。当初は **AI で要約する**前提で、手段として次の4つを検討していた：

1. Claude / ChatGPT の API（従量課金）
2. claude-code-action（Claude のサブスクリプション枠内）
3. Amazon Bedrock（従量課金だが請求が AWS に統合される）
4. GitHub Copilot

しかし要求を分解すると、混ざっていた2つの要求が見えた：

- **要求A: リソースの列挙** — 「何が create / update / delete されるか」を一覧したい。
- **要求B: 意味づけ** — 「この変更は何者で、何が危険か」を人間の言葉で語ってほしい。

ヒアリングの結果、欲しかったのは **要求A だけ**だった（細かい差分は GitHub のソース変更履歴で追える）。

ここで重要なのは、Terraform は `terraform show -json <planfile>` で**構造化された JSON** を出せる点。`resource_changes[].change.actions`（`create` / `update` / `delete` / `["delete","create"]`=replace / `no-op` / `read`）を読めば、要求A は `jq` で**完全に決定的**に組み立てられる。GitHub Actions の Summary は Markdown なので、色付け問題も解消する。AI がコストと引き換えに価値を出すのは要求B のみであり、今回は不要。

## 決定

**AI は使わず、`terraform show -json` の出力を `jq` でパースして Markdown 表を組み立て、`$GITHUB_STEP_SUMMARY` に書き出す。** 共通処理は Composite Action に切り出す。

- **粒度はレベル1（値を出さない）**：アクション種別・リソースアドレス・集計（`N to add, N to change, N to destroy`）のみ。`before`/`after` の値は出さない。理由は秘密漏洩の回避 → 後述。
- **3段構成に統一**：両ワークフローを `terraform plan -out=tfplan` → 要約 → `terraform apply tfplan` にする。`preview-create.yml` には現状 plan ステップが無いので新設する。保存したプランをそのまま apply するため、plan と apply の再計算による乖離も消える。
- **共有は Composite Action**：`.github/actions/tf-plan-summary/`（入力: plan ファイル名・作業ディレクトリ・タイトル）。中で `terraform show -json` まで実行し Summary に追記する。呼ぶ側は `- uses: ./.github/actions/tf-plan-summary` の1行。
- **失敗時はフェイルクローズ**：要約ステップを apply の手前に置くので、`set -euo pipefail` のまま要約が失敗すればジョブが止まり apply はスキップされる。追加のエラーハンドリングは不要。デプロイに緊急性は無く、誤って apply するより止める方が安全という判断。

## 考慮した代替案

- **① Claude / ChatGPT の API**。自然言語で要約でき柔軟。**却下理由**: 従量課金。plan 出力（リソース名・ARN・アカウント ID 等のインフラ詳細）を外部 API に送る＝第三者送信になり、CLAUDE.md の「Secrets / 資格情報を露出しない」ガードレールと相性が悪い。要求A には過剰。
- **② claude-code-action（サブスク枠内）**。追加課金なし。**却下理由**: 本来 `@claude` メンションでコーディングエージェントとして動く重い仕組みで、plan の要約だけに使うのは過剰。CI での非対話利用やトークン運用にも難がある。
- **③ Amazon Bedrock**。請求が AWS に統合され、データが AWS 内に留まる（外部送信リスクは①より低い）。既存の OIDC 認証基盤とも相性が良い。**却下理由**: それでも従量課金で、要求A はそもそも AI 不要。将来 要求B（リスクの言語化）が欲しくなったら、外部送信を避けられる本案が第一候補になりうる。
- **④ GitHub Copilot**。**却下理由**: 料金・モデル・CI からの利用形態が未調査で、いずれにせよ要求A には AI 自体が不要。
- **値の差分も出す（レベル2）**。「どう変わるか」まで分かる。**却下理由**: `terraform show -json` は人間向けの `terraform plan` と違い `sensitive` 値を `(sensitive value)` に伏せず、`before`/`after` に**生値**が入る（どこが秘密かは `after_sensitive` 等で別途示されるだけ）。素朴に出すと DB パスワードや `mail_preview_redirect_to` 等が Summary に平文で出る。伏字処理を自前で書くのは要求A には過剰。

## トレードオフ / 影響

- **AI が要求されたのに AI を使わない**ため、初見では「なぜ AI じゃない？」と見える（本 ADR がその理由）。経緯＝「依頼は AI 要約だったが、要求を分解したら要求A だけで AI 不要だった」を残すのが本 ADR の主目的。
- `jq` が想定外だが正常な plan で取りこぼすと、本来通せるデプロイも止まる（フェイルクローズの代償）。緊急性が無い前提で許容。
- レベル1なので「どう変わるか（値の差分）」は Summary では分からない。差分は GitHub のソース変更履歴で追う前提。
- 将来 要求B（変更の意味・リスクの言語化）が必要になったら、外部送信を避けられる **③ Bedrock** を第一候補に再検討する余地を残す。
- `preview-create.yml` の apply を `terraform apply tfplan` に変えるため、plan 時に同じ `-var`（`pr_number` / `image_tag_*` / `mail_preview_redirect_to`）を渡してプランを作る必要がある（変数の渡し漏れは plan 段階で顕在化する）。
