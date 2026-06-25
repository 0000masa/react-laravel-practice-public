---
status: accepted
---

# 検証環境のフロントは PR ごとに CloudFront を新規作成する

## 背景

PR ごとの検証環境（[preview 環境](../deploy/pr-preview-environment.md)）で React SPA を配信する方式を検討した。本番は S3 + CloudFront（SPA）と ALB/ECS（`/api/*`）を分離した構成で、これを「本番相当の正式構成」としてテストしたい。

候補は 2 つあった。

- **B1**: PR ごとに CloudFront ディストリビューションを新規作成し、viewer = `pr-<n>.preview.<domain>` とする。
- **B2**: `*.preview.<domain>` 用の CloudFront を 1 枚だけ共有し、CloudFront Function で Host → S3 プレフィックス（`/pr-<n>/`）を書き換えて振り分ける。

## 決定

**B1（PR ごとに CloudFront を新規作成）を採用する。**

- viewer ホスト（`pr-<n>.preview`）と API オリジンホスト（共有 `preview-api`）を分け、`all_viewer` ポリシーで Host を ALB に転送して PR を識別する（本番の `www` / `api` 分離と同じ理屈）。
- 配信トポロジ（S3+CloudFront / `X-CloudFront-Secret` による 403 ゲート / SPA フォールバック関数）を**本番と同形**で再現する。

## 考慮した代替案

- **B2（共有 1 枚 + CloudFront Function 書き換え）**: PR ごとのリソースが軽量で作成/削除が速い。**却下理由**: 本番に無い「Host→プレフィックス書き換え」というエッジロジックが 1 段増え、実挙動が本番とわずかにズレる懸念がある。検証環境は本番相当の忠実性を最優先したいため採らない。

## トレードオフ / 影響

- CloudFront の**新規作成は数分、削除は disable→削除で十数分**かかる。「PR クローズで即時に消える」性質は犠牲になる（許容する）。
- 同時 preview 数は ALB のルール/ターゲットグループ枠と CloudFront の数に縛られる。**上限 20** を設けて運用する。
- B2 で必要だった CloudFront Function（書き換え）は不要。SPA フォールバック関数は本番と同じものを各ディストリビューションに付けるだけで、これは本番との差分にならない。
