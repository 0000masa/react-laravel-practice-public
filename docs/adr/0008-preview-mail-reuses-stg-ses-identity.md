---
status: accepted
---

# preview のメール送信は専用ドメインを検証せず、stg の検証済み SES アイデンティティから送る

## 背景

[preview 環境](../deploy/pr-preview-environment.md)は閲覧用に `pr-<n>.preview.<domain>` という専用サブドメインを持つ（親は `preview_zone_apex` = `preview.<domain>`）。一方アプリはメール送信に SES を使い、SES は「**From のドメインに一致する検証済みアイデンティティ**」を要求する。

SES で検証済みのドメインは `terraform/modules/app-infrastructure/ses.tf` の1つだけで、`${sub_frontend_domain_name}.<domain>`（例 `stg.www.mylabinfra.com`）。DKIM・MAIL FROM・DMARC の Route53 レコードもこのドメイン配下にしか無い。preview の閲覧ドメイン `preview.<domain>` は SES 未検証で、`stg.www.<domain>` の子サブドメインでもないため、`noreply@preview.<domain>` を From にすると SES が `MessageRejected`（未検証）で弾く。

PR ごとに使い捨てる preview のために、PR/サブドメイン単位で SES ドメイン検証（検証 TXT + DKIM の Route53 レコード追加、検証完了待ち）を行うのは運用コストが高く、検証環境の趣旨（本番相当の挙動確認）に対して過剰。

## 決定

**preview は専用ドメインを SES 検証せず、From を stg の検証済みアイデンティティ（`noreply@${sub_frontend_domain_name}.<domain>`）に向けて送る。Route53 への SES レコード追加は行わない。**

- From ドメインはモジュール output `ses_domain_identity_name` を `stg → pr-env`（`terraform_remote_state`）で渡し、`pr-env/locals.tf` の `MAIL_FROM_ADDRESS` に焼き込む（ハードコードしない）。
- SES 送信権限は **2 階建て**で付与する。実効権限は per-PR ロールのポリシーと Permissions Boundary の積集合になるため、両方に `ses:SendEmail`/`ses:SendRawEmail` が必要:
  - per-PR タスクロール（`pr-env/iam.tf` の `SesSend`）: `Resource` を stg SES identity ARN（output `ses_domain_identity_arn`）に絞る。
  - Permissions Boundary（`stg/preview_shared.tf` の `PreviewRuntimeMax`）: 天井として `ses:SendEmail`/`ses:SendRawEmail` を許可（`Resource = *`）。
- 誤送信・濫用の被害半径は、`AppServiceProvider` の `Mail::alwaysTo(preview_redirect_to)` による**全宛先の固定アドレス上書き**で限定する。

## 考慮した代替案

- **B: preview ドメイン（`preview.<domain>`）を SES ドメイン検証する**。検証すれば `pr-<n>.preview.<domain>` も子サブドメインとして送信元に使え、From が閲覧ドメインと揃って自然。**却下理由**: 検証 TXT + DKIM(3本) + MAIL FROM(MX/SPF) の Route53 レコードと検証完了待ちが必要で、使い捨て検証環境には運用コストが過剰。本番相当の「挙動」確認には From ドメインの一致は不要。
- **C: Boundary を広げず per-PR ロールにだけ SES を足す**。**却下理由**: 実効権限は Boundary との積集合なので、天井に SES が無いと足しても無効（机上では権限があるのに動かない、最も分かりにくい失敗）。

## トレードオフ / 影響

- preview のメール From が **閲覧ドメインと違う stg ドメイン**になる（受信メールのヘッダ上、見かけ上ちぐはぐ）。検証用途では許容。用語の区別は [terraform/CONTEXT.md](../../terraform/CONTEXT.md) の「閲覧ドメイン」「メール送信元ドメイン」を参照。
- SES が**サンドボックス**の間は、From（検証済み stg ドメイン）に加えて宛先（`PREVIEW_MAIL_REDIRECT_TO`）も SES で検証済みである必要がある。
- Boundary に SES を足すことで、任意の per-PR ロールが理論上 SES 送信できる天井になる。ただし per-PR ロール本体は identity ARN にスコープし、アプリは宛先を固定上書きするため被害半径は限定的。
- stg に新 output（`ses_domain_identity_arn` / `_name`）を追加したため、**stg を先に apply** してから pr-env を apply する順序依存が生じる。
