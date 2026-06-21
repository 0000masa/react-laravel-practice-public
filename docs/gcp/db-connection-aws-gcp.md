# DB 接続方式の比較（ECS+RDS / Lambda+RDS Proxy / Cloud Run+Cloud SQL）

アプリ（コンテナ・関数）から DB に接続するときの **接続経路・認証・アプリ側設定（環境変数）・IAM の役割**を、
3 構成で比較する。`ECS+RDS` と `Cloud Run+Cloud SQL` は**この repo の実構成**、
`Lambda+RDS Proxy+RDS` は**この repo には無い**一般知識としての比較対象。

---

## まず結論（メンタルモデルの補正）

接続は **「① ネットワーク到達」+「② 認証」** の2段で考えると整理しやすい。両者で「IAM が出てくる場所」が違う。

| | ① ネットワーク到達の手段 | ② DB へのログイン認証 | IAM が関与する場所 |
| --- | --- | --- | --- |
| **ECS + RDS**（本 repo / AWS） | VPC 内 + セキュリティグループ（SG）で到達 | MySQL ユーザー / パスワード | **DB 接続には不要**。IAM が要るのは ECS 実行ロールが SSM から `DB_PASSWORD` を読む所だけ |
| **Lambda + RDS Proxy + RDS**（参考） | VPC + SG で Proxy に到達 | Lambda→Proxy は **IAM 認証トークン**、Proxy→RDS は ユーザー / パスワード（Proxy が Secrets Manager から取得して保持） | **接続経路そのものに IAM**（Lambda は DB パスワードを持たない） |
| **Cloud Run + Cloud SQL**（本 repo / GCP） | Cloud SQL コネクタ（Auth Proxy）の **Unix ソケット**。VPC 不要 | MySQL ユーザー / パスワード（Secret Manager） | **トンネルの認可に IAM**（`roles/cloudsql.client`）。ただし**パスワードは別途必要** |

補正ポイント:

1. **ECS→RDS は「ARN」では繋がない。** 繋ぐのは **エンドポイント（ホスト名）:3306**。ARN は IAM や
   シークレット参照のための識別子で、接続文字列には使わない。DB 接続自体に IAM は登場しない
   （到達は SG、認証はパスワード）。
2. **Cloud SQL コネクタの `roles/cloudsql.client` は「パスワードの代わり」ではない。**
   これは**暗号化トンネルを張る認可**であって、その先で**アプリは依然ユーザー/パスワードでログインする**。
   つまり IAM（経路の認可）+ パスワード（DB 認証）の**2層**。
3. **「Cloud SQL コネクタ ≒ Lambda+RDS Proxy の IAM 接続」は半分だけ正しい。**
   - 似ている点: どちらも IAM で接続経路を認可し、アプリ/関数が**静的な DB 認証情報を持たずに**経路を確立できる。
   - 違う点: **RDS Proxy は認証情報を Proxy 側が保持**するので Lambda はパスワード不要。
     一方 **Cloud SQL コネクタは認証情報を保持しない**ので、**アプリが依然パスワードを渡す**。
   - 「IAM だけで完全にパスワードレス」にしたいなら、別物の
     **Cloud SQL IAM データベース認証**（後述）が対応する。この repo は使っていない。

---

## 1. ECS + RDS（本 repo / AWS）

- **DB 側**: RDS は `publicly_accessible = false`、プライベートサブネット（`aws_db_subnet_group`）に配置、
  セキュリティグループ `rds_sg` で ECS からの 3306 だけ許可。→ **到達制御は純粋にネットワーク（VPC + SG）**。
- **接続経路**: ECS タスク（同一 VPC）から RDS の**エンドポイント（ホスト名）** に直接 TCP 接続。プロキシ無し。
- **アプリ側設定（環境変数）**: `ecs_web.tf` の `environment` / `secrets` で注入。

  | 変数 | 出どころ | 注入方法 |
  | --- | --- | --- |
  | `DB_HOST` | `aws_db_instance.main.address`（RDS エンドポイント） | environment（平文） |
  | `DB_PORT` `DB_DATABASE` `DB_USERNAME` `DB_CONNECTION` | 固定 / 変数 | environment（平文） |
  | `DB_PASSWORD` | **SSM Parameter Store**（`data.aws_ssm_parameter.db_password.arn`） | **secrets**（ECS が実行時に値を取得して環境変数として注入） |

- **認証**: 標準の MySQL ユーザー/パスワード。**IAM DB 認証は不使用**。
- **IAM の役割**: DB 接続経路には関与しない。**ECS タスク実行ロール**が SSM パラメータを読むために IAM 権限を持つ、
  という所だけ（＝シークレット取得のための IAM であって、DB 認証の IAM ではない）。
- **Laravel 側**: `config/database.php` の mysql 接続が `DB_HOST`（TCP）を使う。

> まとめ: **到達 = VPC + SG / 認証 = パスワード / IAM = DB 接続には出てこない**。一番素直な「昔ながら」の形。

## 2. Lambda + RDS Proxy + RDS（参考・本 repo には無い）

Lambda は起動のたびに短命な接続を大量に張るため RDS の接続数を食い潰しやすい。そこで間に **RDS Proxy**
（接続プール + 認証の仲介）を挟む構成がよく採られる。

- **接続経路**: Lambda（VPC 内）→ RDS Proxy → RDS。SG で到達制御。
- **認証**:
  - **Lambda → Proxy**: **IAM 認証**（IAM で短命なトークンを取得して Proxy に提示）。Lambda は DB パスワードを持たない。
  - **Proxy → RDS**: Proxy が **Secrets Manager から DB ユーザー/パスワードを取得して保持**し、それで RDS にログイン。
- **アプリ側設定（環境変数）**: 接続先ホストを **Proxy のエンドポイント**にする。IAM 認証なら
  パスワードの代わりに「IAM トークンを生成して渡す」コードが必要（SDK / ドライバのプラグイン）。
- **IAM の役割**: **接続経路の認証そのもの**に IAM が入る（DB パスワードをアプリから排除できる）。

> まとめ: **到達 = VPC + SG / 認証 = Lambda は IAM トークン・Proxy はパスワード / IAM = 接続の認証に直接関与**。
> 「アプリが DB パスワードを持たない」を実現する AWS 側の代表的な形。

## 3. Cloud Run + Cloud SQL（本 repo / GCP）

VPC を作らない方針のため、**Cloud SQL コネクタ（Cloud SQL Auth Proxy）**で接続する。
コネクタが暗号化トンネルを張り、Cloud Run からは **Unix ソケット**として見える。

- **DB 側**: `cloud_sql.tf` は公開 IP 有効（`ipv4_enabled = true`）だが **`authorized_networks` は空**、
  `ssl_mode = ENCRYPTED_ONLY`。→ **直接 TCP では誰も入れない。コネクタ経由だけ**が通る。
- **接続経路**: Cloud Run サービスに Cloud SQL インスタンスを紐付けると、`/cloudsql/<connection_name>` という
  ソケットがマウントされる（`cloud_run.tf` の `volumes { cloud_sql_instance {...} }` →
  `volume_mounts { mount_path = "/cloudsql" }`）。アプリはこのソケットに繋ぐ。
- **アプリ側設定（環境変数）**: `cloud_run.tf` の `run_env`。

  | 変数 | 値 | 注入方法 |
  | --- | --- | --- |
  | `DB_SOCKET` | `/cloudsql/<connection_name>`（= TCP ホストではなく**ソケットパス**） | env（平文） |
  | `DB_CONNECTION` `DB_DATABASE` `DB_USERNAME` | 固定 / 変数 | env（平文） |
  | `DB_PASSWORD` | **Secret Manager**（`db_password`） | secret 参照（実行時に注入） |

- **認証（2層）**:
  - **① トンネルの認可 = IAM**: 実行 SA `practice-gcp-stg-run` が `roles/cloudsql.client` を持つ。
    これが無いとコネクタがトンネルを張れない（`PERMISSION_DENIED`）。Cloud Run は SA の ADC（キーレス）で認可。
  - **② DB ログイン = ユーザー/パスワード**: トンネルの先で、`DB_USERNAME` + `DB_PASSWORD`(Secret Manager) で
    MySQL にログイン。**ここはパスワード認証のまま**（IAM DB 認証は未使用）。
- **Laravel 側**: `config/database.php` の mysql 接続が `unix_socket`（= `DB_SOCKET`）を使う。
  `DB_HOST` は使わない（TCP ではなくソケット接続のため）。

> まとめ: **到達 = コネクタの Unix ソケット（VPC 不要）/ 認証 = IAM(経路) + パスワード(DB) の2層 /
> IAM = 経路の認可に関与（ただしパスワードは排除していない）**。

---

## Cloud Run → Cloud SQL の接続手段（全パターンと VPC 依存）

「そもそもどんな手段があるか」「VPC のプライベートサブネットに入っているかで変わるか」への回答。
**変わる。** 大きく分けて以下。

| 手段 | VPC 必要？ | 経路 | IAM | この repo |
| --- | --- | --- | --- | --- |
| **A. Cloud SQL コネクタ（Auth Proxy / Unix ソケット）** | **不要** | コネクタが公開 IP 上に暗号化トンネル → ソケット | `roles/cloudsql.client` が**必要** | **採用** |
| **B. プライベート IP へ直接接続（Direct VPC egress）** | **必要**（Cloud Run を VPC に出す） | VPC 内で Cloud SQL のプライベート IP に直接 TCP | 接続自体に IAM **不要**（到達は VPC、認証はパスワード） | 不採用 |
| **C. プライベート IP へ直接接続（Serverless VPC アクセスコネクタ）** | **必要**（VPC コネクタを別途作成） | B と同様（古い方式。Direct VPC egress が後継） | 同上、接続に IAM **不要** | 不採用 |
| **D. 公開 IP へ直接接続（authorized_networks）** | 不要 | Cloud SQL の公開 IP に直接 TCP | IAM 不要だが… | 不採用（**非推奨**） |

ポイント:

- **A（コネクタ）**: VPC を持たない本 repo の選択。公開 IP でも**直接 TCP は閉じ**、コネクタの IAM 認可 + TLS で
  守る。「VPC を作らずに安全に繋ぐ」ための GCP 流の答え。**IAM が要るのはこの方式だから**。
- **B / C（プライベート IP 直接）**: Cloud Run を VPC に接続すれば、AWS の ECS→RDS と**同じ発想**（到達は
  ネットワーク、認証はパスワード）で繋げる。この場合 `roles/cloudsql.client` は**不要**。
  **＝「VPC に入っているかどうか」で接続手段も IAM の要否も変わる**、というのが質問への答え。
- **D（公開 IP 直接）**: Cloud Run は送信元 IP が動的で `authorized_networks` を固定しづらく、
  公開面に DB を晒すため実運用では避ける。

> 言い換え: **VPC が無い → コネクタ（A、IAM 必要）/ VPC があってプライベート IP → 直接接続（B・C、接続に IAM 不要）**。
> 本 repo は「VPC を作らない」方針なので A になり、結果として実行 SA に `roles/cloudsql.client` が要る。

---

## 補足: Cloud SQL IAM データベース認証（真のキーレス・本 repo 未使用）

上記 A〜D はいずれも「DB ログインはユーザー/パスワード」。これを**パスワードレス**にするのが
**Cloud SQL IAM データベース認証**。

- DB ユーザーとして **IAM プリンシパル（SA やユーザー）自体**を登録し、ログイン時はパスワードの代わりに
  **IAM の短命トークン**を使う。
- これにより **Secret Manager の `DB_PASSWORD` が不要**になる（②の認証も IAM に寄せられる）。
- AWS でいう **RDS の IAM データベース認証**、あるいは「RDS Proxy への IAM 接続」に発想が近い
  （アプリから静的 DB パスワードを完全に排除）。
- 本 repo は学習用の最小構成として**パスワード方式（Secret Manager）**を採用しており、IAM DB 認証は使っていない。
  将来パスワードレス化したい場合の発展先として記録。

---

## AWS ⇔ GCP 対応まとめ

| 観点 | ECS + RDS | Lambda + RDS Proxy | Cloud Run + Cloud SQL（本 repo） |
| --- | --- | --- | --- |
| 到達 | VPC + SG | VPC + SG（Proxy 経由） | コネクタの Unix ソケット（VPC 不要） |
| 接続先指定 | RDS エンドポイント（host:3306） | Proxy エンドポイント | `/cloudsql/<connection_name>`（ソケット） |
| DB 認証 | ユーザー/パスワード | Lambda は IAM トークン / Proxy はパスワード | ユーザー/パスワード（Secret Manager） |
| 接続経路の IAM | 不要 | **必要**（Lambda→Proxy） | **必要**（`roles/cloudsql.client`） |
| パスワードのアプリ保持 | する（SSM 経由で注入） | しない（Proxy が保持） | する（Secret Manager 経由で注入） |
| パスワードレス化の道 | RDS IAM DB 認証 | 既に IAM 接続 | Cloud SQL IAM DB 認証 |

> 関連: 実行 SA に付けるロールの詳細は [manual-setup-console.md](./manual-setup-console.md) 手順6、
> シークレットの扱いは同手順4を参照。
