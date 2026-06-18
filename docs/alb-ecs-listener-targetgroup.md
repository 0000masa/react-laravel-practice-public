# ALB と ECS の紐付け（リスナー / リスナールール / ターゲットグループ / ECSサービス）

`terraform/modules/app-infrastructure/alb.tf` / `ecs_web.tf` / `ecspresso/stg/web/service-def.jsonnet` の構成を言語化したメモ。

## 各要素の役割

| 要素 | 役割 | このリポジトリでの実体 |
|---|---|---|
| **リスナー** | 「何番ポートで待ち受けるか」+ TLS証明書 | 443(HTTPS)で待受。80はHTTPS(301)へリダイレクト。どのルールにもマッチしなければ **default_action = 403** |
| **リスナールール** | リスナーにぶら下がり、**条件にマッチしたら → どのTGへ forward** するかを決める(ルーティング) | `X-CloudFront-Secret` ヘッダ一致を条件に slot_a へ forward |
| **ターゲットグループ(TG)** | 実際の宛先プール。**ヘルスチェックもTG単位** | slot_a / slot_b、`/api/health` で200判定 |
| **ECSサービス** | **自分のタスクのIPをどのTGに登録するか**を決める(メンバーシップ) | `load_balancer` ブロックで指定 |

## ニュアンス① 「リスナールール→TG」と「ECSサービス→TG」は別物

両方とも「TGを指定」に見えるが、**役割が違う2つの紐付け**。

- **リスナールール → TG** = ルーティング(「このリクエストをどのTGへ送るか」)
- **ECSサービス → TG** = 登録(「このサービスのタスクIPをどのTGに入れるか」)

両者が**同じTGを指して初めて**、リクエストが実際のタスクに届く。片方だけでは通信は成立しない。
「ルールは forward 先を決める」「サービスは TG の中身(タスク)を埋める」と分けて捉えると正確。

## ニュアンス② この構成はECSネイティブBlue/Greenなので、もう一段ある

普通の Rolling なら「1サービス → 1TG、ルールは固定」で終わる。
ここは Blue/Green なので **TGが2つ(slot_a / slot_b)** あり、ECSサービス側(`ecs_web.tf` / `service-def.jsonnet`)が次を持つ。

- `target_group_arn = slot_a`(本番)
- `alternate_target_group_arn = slot_b`(切替先)
- `production_listener_rule` / `test_listener_rule` の **ARNまで直接参照**

デプロイ時は **ECS自身が新リビジョンを slot_b に立て、リスナールールの weight を slot_a → slot_b に書き換えて** トラフィックを切り替える。

そのため `aws_lb_listener_rule` にも `aws_ecs_service` にも `lifecycle { ignore_changes }` が付いている。
→ **ECSが実行時に weight を書き換えるのを、Terraform が drift とみなして元に戻さないようにする**ため。

## 1文まとめ

> リスナー(443で待受)にリスナールールを付け、**ルールが条件マッチ時の forward 先TGを決める**。**ECSサービスは自タスクのIPをそのTGに登録する**。本構成はB/Gなので **TGを2つ用意し、ECS自身がリスナールールの weight を切り替えて** Blue→Green を行う(だから両者は `ignore_changes`)。
</content>
