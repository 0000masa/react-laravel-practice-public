---
status: accepted
---

# stg/preview の Basic 認証は WAF ではなく CloudFront Function で行い、WAF は全環境で1枚に集約する

## 背景

stg と preview は外部に公開してはいけないため Basic 認証を掛けたい。守るべき公開面は **frontend CloudFront のみ**（`stg.api` への ALB 直叩きは `X-CloudFront-Secret` ヘッダ必須で 403 ゲート済み）。

当初は CloudFront 用 WAF が2枚あった：共有モジュール `modules/app-infrastructure/waf.tf` の `cloudfront_waf`（AWS マネージドルール＝攻撃遮断）と、stg ルート `preview_shared.tf` の `preview_basic_auth`（Basic 認証）。stg frontend は前者だけを使っており **Basic 認証が無かった**（公開状態）。

Basic 認証を共有モジュールの WAF に直接書くと、将来の prod ルートにも適用されてしまう（prod は公開が要件）。また **1つの CloudFront に付けられる Web ACL は1枚だけ**なので、「マネージド WAF」と「Basic 認証 WAF」を同一ディストリビューションに重ね付けできず、Basic 認証を WAF でやるなら「マネージド＋Basic を1枚に統合した Web ACL」を別途作る必要がある。

WAF の課金は **Web ACL 単位**（$5/月＋ルール $1/月、関連付け数には非依存）。Basic 認証用に2枚目の Web ACL を持つと固定費が増える。

## 決定

**Basic 認証は CloudFront Function で行い、WAF（`cloudfront_waf`）は prod/stg/preview 共通の1枚（マネージドルール専用）に集約する。**

- module の `spa_fallback`（viewer-request 関数）に、SPA フォールバックの前段として Basic 認証判定を差し込む。`var.enable_basic_auth`（bool）で生成を切り替え、関数は default と `/api/*` の**両ビヘイビア**に付与する（関数はビヘイビアごとなので両方に付けないと API パスが素通りする）。
- stg ルートは `enable_basic_auth = true`、資格情報（SSM の生 `user:pass`）を `basic_auth_credential` で module に渡す。preview の CloudFront は stg の output 経由で**同じ関数 ARN を共有**するため自動的に認証付きになる。prod ルート（将来）は既定の `false` で公開のまま。
- 認証情報は CF Functions が実行時に SSM を読めないため、apply 時に `base64encode()` した `Basic <b64>` を関数コードへ焼き込み、受信 `Authorization` ヘッダと完全一致で判定する（WAF の `search_string` と同じ考え方）。
- 役割を分離する：**WAF = 攻撃遮断（マネージドルール）、CloudFront Function = アクセス制限（Basic 認証）**。`preview_basic_auth` Web ACL は廃止し、preview も `cloudfront_waf` を使う。

## 考慮した代替案

- **② WAF を2枚（マネージド専用＋「マネージド＋Basic」統合）にし、stg/preview は統合版を共有**。WAF ネイティブで実装は素直、ディストリビューション全体を一律保護できる。**却下理由**: 2枚目の Web ACL で固定費 ~$6/月が増える。管理対象（Web ACL）も増える。Basic 認証だけが目的なら CF Function で十分。
- **③ 既存の `cloudfront_waf` に「ルールを足したもの」を stg/preview だけに使う**。**却下理由**: Web ACL のルールセットは固定で、付与先ごとにルールを差し込むことはできない。「ベース＋追加」は結局 (マネージド＋Basic) を持つ別 Web ACL を作るのと同じで、コストは②と同一（③は②に吸収）。`aws_wafv2_rule_group` でコード重複は減らせるが Web ACL の枚数＝課金は減らない。

## トレードオフ / 影響

- Basic 認証ロジックが「SPA フォールバック関数」に同居するため、初見では「なぜ認証が SPA 書き換え関数に？なぜ WAF でない？」と見える（本 ADR がその理由）。
- CF Functions はビヘイビアごとなので、保護したいビヘイビア（default と `/api/*`）すべてに関数を付ける必要がある。付け忘れは認証バイパスになる。
- 資格情報は関数コードに焼き込まれ、`cloudfront:GetFunction` で読める。これは WAF の `wafv2:GetWebACL` で `search_string` が読めるのと同クラスの露出で、Basic 認証＋HTTPS 前提では許容。
- 共有モジュールに認証ロジックを持つが、prod は `enable_basic_auth=false` で構造的に無効（漏れない）。考え方は ADR 0007 の「環境差はフラグで表現」と同系統。
- マネージド WAF を preview にも付けることで、QA 中に攻撃的に見えるペイロードがマネージドルールで弾かれる可能性がある（stg と同条件）。
- apply 順序の注意：稼働中の preview がある状態で `preview_basic_auth` Web ACL を削除すると「関連付け中の Web ACL は削除不可」で失敗するため、各 preview を先に再 apply（`web_acl_id` を `cloudfront_waf` へ切替＋関数付与）してから stg を apply して旧 WAF を削除する。
