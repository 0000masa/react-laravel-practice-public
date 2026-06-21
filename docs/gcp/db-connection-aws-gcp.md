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
**変わる。** ただし整理のため、**接続方式は独立した2軸**で考える。

### 接続方式は 2 軸（経路 × 認証）

| 軸 | 何を決めるか | 選択肢 |
| --- | --- | --- |
| **A. 接続経路（ネットワーク到達）** | パケットがどう Cloud SQL に届くか | ① コネクタ（Auth Proxy / Unix ソケット）② プライベート IP 直接（VPC 必須）③ 公開 IP 直接（非推奨） |
| **B. 認証（どうログインするか）** | DB にどう認証するか | ㋐ ユーザー/パスワード（Secret Manager）㋑ IAM データベース認証（パスワードレス） |

- **VPC 有無が効くのは軸 A だけ**。VPC なし → ① コネクタ。VPC あり → ② プライベート IP が選べ、本番では推奨。
- **軸 B は VPC 有無と無関係**。IAM DB 認証は「経路」ではなく「認証」なので、**コネクタ経由でも**選べる
  （＝ VPC なしのままパスワードレス化も理屈上は可能）。
- **本 repo は ①（コネクタ）×㋐（パスワード）** の組み合わせ。

### 実務でどれが使われるか

- **経路（軸 A）**: Cloud Run では **① コネクタが最も採用例が多い**（Google 公式の Cloud Run + Cloud SQL 手順も
  これ。VPC 不要・追加インフラ不要で低コスト）。一方、**セキュリティ重視の本番・大きめの組織は
  ② プライベート IP**（DB に公開 IP を一切持たせず攻撃面を最小化）を本番ベストプラクティスとして使う。
  「**Cloud Run の定番＝①／本番堅牢＝②**」で割れているのが実情。
- **認証（軸 B）**: **㋐ パスワード + Secret Manager が今も最も一般的なベースライン**。特に **PHP/Laravel では
  圧倒的に主流**（理由は後述）。㋑ IAM DB 認証は「静的パスワードを廃する」現代的ベストプラクティスで、
  Go/Java など公式コネクタのある言語を中心に採用が伸びている。

> 本 repo（Cloud Run + Laravel）の ①×㋐ は、**「Cloud Run + PHP の実務の主流」をそのまま採用**している。
> 経路を②に上げるには VPC が必要で [ADR 0001](../adr/0001-gcp-cloudrun-novpc-core.md)（VPC なし）の前提を覆す。

### 経路（軸 A）の選択肢一覧

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

## 認証（軸 B）: Cloud SQL IAM データベース認証を採用しなかった理由

軸 A（経路）はコネクタ、軸 B（認証）はパスワード + Secret Manager を採用した。ここでは
**パスワードレスの代替㋑（IAM DB 認証）が何で、なぜ今回採らなかったか**を記録する。

### IAM DB 認証とは

- DB ユーザーとして **IAM プリンシパル（SA やユーザー）自体**を登録し、ログイン時はパスワードの代わりに
  **IAM の短命トークン（有効 1 時間）**を使う。
- これにより **Secret Manager の `DB_PASSWORD` が不要**になり、静的 DB パスワードをアプリから完全排除できる。
- AWS の **RDS IAM データベース認証**や「RDS Proxy への IAM 接続」に発想が近い。
- 経路とは独立なので、**コネクタ経由のまま（VPC なしのまま）でも**適用できる。

### PHP/Laravel で採用するとかかる手間

セキュリティ思想としては優れるが、**PHP では非標準ルートになり手間が大きい**。

1. **公式コネクタライブラリが PHP に無い。** Go / Java / Python / Node には Cloud SQL Language Connector が
   あり IAM トークンを自動処理できるが、**PHP 用は存在しない**。
2. **Cloud Run ビルトインの Cloud SQL 連携（今の socket マウント方式）は `--auto-iam-authn` を露出しない。**
   つまり「ソケットをマウントするだけで IAM 認証」とはならない。
3. 結果、Laravel でやるには次のどちらかの追加実装が必要:
   - **Cloud SQL Auth Proxy をサイドカーコンテナとして自前起動**し、`--auto-iam-authn` を付けて動かす
     （ビルトイン連携をやめ、コンテナ構成・起動順・リソースを自分で管理）。
   - もしくは **アプリ側で IAM アクセストークンを生成**し、それを PDO のパスワードとして渡す。トークンは
     **1 時間で失効**するため、**接続のたびに/期限前に再取得するロジック**を Laravel に組み込む必要がある
     （PDO は接続時にパスワードを固定するため、コネクションプール/再接続との相性も考慮が要る）。
4. DB 側に **IAM ユーザーの作成とマッピング**、SA への `roles/cloudsql.instanceUser`（+ `cloudsql.client`）付与など、
   付随設定も増える。
5. **認可（権限）は別レイヤーで、`GRANT` を自分で実行する必要がある。** IAM が肩代わりするのは
   **認証（誰としてログインするか）だけ**。IAM ユーザーは**最小権限（実質 USAGE＝接続できるだけ）**で
   作られるため、管理者で DB に入り明示的に権限を付与するブートストラップが要る。
   本 repo の構成（DB `practice_db` / 実行 SA `practice-gcp-stg-run`）なら、例えばこうなる:

   ```sql
   -- 管理者ユーザー（例: admin）で接続してから実行する。
   -- ① サービスアカウントの DB ユーザー名は「SA のメール − .gserviceaccount.com」。
   --    SA: practice-gcp-stg-run@<PROJECT_ID>.iam.gserviceaccount.com
   --    →  DB ユーザー名: 'practice-gcp-stg-run@<PROJECT_ID>.iam'

   -- ② アプリ実行に必要な DML を付与（読み書きのみ）
   GRANT SELECT, INSERT, UPDATE, DELETE
     ON practice_db.*
     TO 'practice-gcp-stg-run@<PROJECT_ID>.iam';

   -- ③ マイグレーション（artisan migrate）も同じ SA で流すなら DDL も必要
   GRANT CREATE, ALTER, DROP, INDEX, REFERENCES
     ON practice_db.*
     TO 'practice-gcp-stg-run@<PROJECT_ID>.iam';

   FLUSH PRIVILEGES;
   ```

   > 注: IAM ユーザーは Cloud SQL 側で先に作成しておく（コンソール / `gcloud sql users create --type=CLOUD_IAM_SERVICE_ACCOUNT`
   > / Terraform の `google_sql_user` で `type = "CLOUD_IAM_SERVICE_ACCOUNT"`）。その後にこの `GRANT` を実行する。
   > マイグレーションを権限の強い別ユーザーで流すなら、実行 SA には ③ の DDL を付けず ② だけに絞るのが安全。

   > 対比: **Cloud SQL Admin API（`google_sql_user` / コンソール）で作った“通常ユーザー”は広い既定権限が
   > 自動付与される**ため、本 repo の `admin`（パスワード方式）は上記 `GRANT` なしで動く。IAM ユーザーだけ
   > 既定権限が最小なので、この GRANT 作業が**パスワード方式には無かった追加の手間**になる。

### 採用しなかった判断

- **PHP/Laravel on Cloud Run の実務主流は㋐（パスワード + Secret Manager）**。本 repo の目的は
  「実務で使う技術の練習」であり、主流から外れる非標準ルートを採る動機が薄い。
- 上記のサイドカー/トークン再取得は、[ADR 0001](../adr/0001-gcp-cloudrun-novpc-core.md) が掲げる
  **「最小構成・ECS より単純」**という主目的に逆行する（複雑性の追加）。
- パスワードは **Secret Manager で管理し、TF が生成・ローテーション可能**なので、静的パスワードといっても
  平文ハードコードではなく、実務的に十分なレベルでは守れている。

> したがって本 repo は **①コネクタ × ㋐パスワード**を維持する。IAM DB 認証は「公式 PHP コネクタが出る」
> 「ビルトイン連携が `--auto-iam-authn` に対応する」等で手間が下がったら再検討する**発展先**として記録。
> パスワードレスを今すぐ厚くしたい場合は、まず軸 A を②プライベート IP に上げて公開 IP 面を消す方が、
> PHP では費用対効果が高い（ただし VPC が必要＝別 ADR）。

### コネクタのある言語（Go / Java / Python / Node）では選好が逆転する

不採用の判断は **PHP 固有**である点に注意。これらの言語には公式 Cloud SQL Language Connector があり、
**IAM トークンの取得・キャッシュ・自動更新をライブラリが肩代わり**する（フラグ 1 つ。例
`enableIamAuth=true` / `WithIAMAuthN()`）。すると PHP で重荷だった「トークン再取得」「Auth Proxy
サイドカー自前起動」が消え、**静的パスワードの保管・ローテも不要**になる。

そのため **GCP 上で動かす新規アプリがこれらの言語なら、IAM DB 認証が第一候補**になりうる
（安全＝静的シークレットなし、かつ実装はほぼ同等の手軽さ）。Google も近年この方向を推奨している。

ただし言語が変わっても次は残る:

- **`GRANT` による認可は依然必要**（IAM は認証だけ。上記の DB 側権限付与は言語に関係なく要る）。
- **IAM DB 認証は GCP 固有**。ローカル開発・CI・他クラウドでコードを共有するなら、パスワードの
  フォールバックが要る。実務では「**本番 = IAM 認証 / ローカル = パスワード**」のハイブリッドが現実解。

> まとめ: **「IAM 認証がシンプル・安全になるか」は言語のコネクタ有無で大きく変わる**。PHP（コネクタなし）
> ではパスワード方式が主流のまま、コネクタのある言語では IAM 認証が第一候補に寄る、という非対称がある。

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
