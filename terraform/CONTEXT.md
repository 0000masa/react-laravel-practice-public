# AWS インフラ

React SPA + Nginx + Laravel を S3 + CloudFront + ALB + ECS + RDS で配信する本番相当の構成（`terraform/stg/` がルート、`terraform/modules/app-infrastructure/` が実体）。用語の正は同モジュールの `.tf`。

## Language

**検証環境（preview 環境）**:
PR ごとに専用サブドメイン `pr-<n>.preview.<domain>` へ立ち上げる、その PR のコードで動く使い捨ての本番相当フルスタック。`preview` ラベルで作成、PR クローズ/ラベル除去で破棄する。詳細は [docs/pr-preview-environment.md](../docs/deploy/pr-preview-environment.md)。
_Avoid_: ステージング（stg は常設の共有環境で別物）、レビューアプリ

**preview ユーザー**:
共通 RDS 上で検証環境が使う MySQL ユーザー。`GRANT ALL ON \`preview\_%\`.*` を持ち、`preview_pr<n>` database を自身で作成/削除できる。stg 本体の database には触れない。
_Avoid_: master ユーザー、アプリユーザー

**スロット（slot_a / slot_b）**:
本番 web サービスの ECS ネイティブ Blue/Green 切替に使う 2 つのターゲットグループ。検証環境では Blue/Green を使わないため登場しない。
_Avoid_: 検証環境のターゲットグループ（そちらは `preview-pr<n>-tg`）
