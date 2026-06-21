---
status: accepted
---

# フロント / 画像は公開バックエンドバケットで配信し、直接 egress 露出を受け入れる

## 背景

`frontend` / `images` バケットは外部 HTTPS LB の**バックエンドバケット**（+ Cloud CDN）として配信する
（[ADR 0001](./0001-gcp-cloudrun-novpc-core.md)）。GCP の外部 LB バックエンドバケットは、オリジンの
オブジェクトが**公開（`allUsers:objectViewer`）でないと読めない**。LB はバケットに認証せず公開オブジェクトを
取得するだけだからで、これは仕様であり回避できない。結果としてオブジェクトは `storage.googleapis.com/...`
への**直接 URL でも誰でも取得可能**になり、CDN を迂回した大量ダウンロードによる egress 課金
（denial-of-wallet）の経路が開く。AWS の S3 + CloudFront + **OAC**（S3 を非公開にし CloudFront 経由のみに
強制）に相当する保護が、GCP のバックエンド"バケット"には存在しない。

## 決定

- `frontend` / `images` は**公開バックエンドバケットのまま**配信する（`allUsers:objectViewer` を付与）。
- 直接 egress リスクは、**課金予算アラート**（[billing-budget-alert.md](../gcp/billing-budget-alert.md)）に
  よる検知と、配信物が小さい（React ビルド成果物）ことによる被害単価の低さで受容する。

## 考慮した代替案

- **プライベートオリジン認証**（GCP 版 OAC 相当）: バックエンド"バケット"を捨て、**バックエンドサービス +
  Internet NEG**（宛先 `<bucket>.storage.googleapis.com:443`）にし、`allUsers` を外して HMAC + SA 読み取りに
  切り替える。直接アクセスは 403 で塞げる。**却下理由**: 構成が大幅に複雑になり、かつ**キャッシュミス時の
  GCS→CDN 転送が internet egress 扱いで追加課金**される。練習用 stg には見合わない。Cloud Armor の
  レート制限もこの構成（全トラフィックを LB に強制）にして初めて意味を持つ。
- **署名付き URL / Cookie**: 公開 SPA の全アセットに署名するのは非現実的。限定配布向けで不適合。

## 影響

- バケットは恒久的に公開。秘匿情報は絶対に置かない（SPA ビルド成果物・公開画像のみ）。
- 本番で大きなメディアを扱う、または wallet 防御が要件化した段階で、プライベートオリジン認証
  （Internet NEG + バックエンドサービス）+ Cloud Armor への移行を再検討する。
