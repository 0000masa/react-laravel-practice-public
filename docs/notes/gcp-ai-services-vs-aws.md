# Google Cloud の AI 関連サービス総覧 —— AWS 対応表つき

チーム技術発表用の配布資料。Google Cloud の AI 関連サービスを 6 つのレイヤーに分けて列挙し、それぞれ「何をするサービスか」「どう使われるか」「AWS でいうとどれに当たるか」をまとめる。AWS 側のサービスも同じ密度で説明しているので、AWS の AI サービスを知らなくても比較できる。

---

## 0. このドキュメントについて

### 読み方

| セクション | 内容 | 想定読者 |
| --- | --- | --- |
| 1. 3 分で読む要約 | 全レイヤーの対応表 1 枚と結論 | 通しで読まない人。発表の導入にも使う |
| 2. レイヤーの定義 | なぜこの 6 分類なのか | 対応表を正しく読むために必要 |
| 3〜8. 各レイヤー | サービス個別の説明と AWS 対応 | 本編 |
| 9. 設計思想の違い | 対応表の「ズレ」から見えるもの | 発表の山場 |
| 10. 用語コラム | AI 特有の用語の定義 | 用語で詰まったときに参照 |
| 11. 参考リンク一覧 | 公式ドキュメントのみ | 後追い調査用 |

### 情報の鮮度と検証方法（重要）

- **調査日: 2026 年 7 月 29 日。**
- 本文に記載した URL は**すべて実際にアクセスして HTTP 200 を確認済み**。
- **2025 年後半から 2026 年前半にかけて、両クラウドとも AI サービスの大規模な改称・世代交代が起きている。** 数か月前の記事やブログの名称は、すでに古い可能性が高い。本資料では、確認できた改称をすべて明記した。
- 記載内容の裏取りレベルは 2 段階ある。混同しないよう、本文中で区別している。
  - **公式ドキュメントの本文で確認済み** …… 引用符つきで原文を併記した箇所
  - **未確認** …… 本文まで取得できなかったもの。各レイヤー末尾の「未確認事項」に列挙した
- **料金は「課金単位」だけを書き、実額（1 トークンあたり何ドル等）は書いていない。** 実額は変動が激しく、資料が数か月で嘘になるため。実際の見積もりは必ず公式の料金ページを参照すること。

---

## 1. 3 分で読む要約

### 全レイヤー対応表

| # | レイヤー | 利用者が持ち込むもの | GCP の主役 | AWS の主役 | 対応の精度 |
| --- | --- | --- | --- | --- | --- |
| L1 | 基盤モデル API | 何も持ち込まない | Gemini API、Model Garden、Imagen、Veo | Amazon Bedrock（自社モデル Amazon Nova を含む） | ◎ ほぼ同等 |
| L2 | ML プラットフォーム | 自分のデータとモデル | Gemini Enterprise Agent Platform の ML 機能群（**旧 Vertex AI**） | Amazon SageMaker AI（**旧 Amazon SageMaker**） | ◎ ほぼ同等 |
| L3 | タスク特化 API | 入力データだけ | Document AI、Speech-to-Text、Vision API、Translation API | Textract、Transcribe、Rekognition、Translate | △ 粒度が違う |
| L4 | データ基盤に統合された AI | データを動かさない | BigQuery ML、BigQuery ベクトル検索、Vector Search、AlloyDB AI | Redshift ML、OpenSearch、Aurora pgvector、S3 Vectors | △ 粒度が違う |
| L5 | エージェント／企業内検索 | 社内データと道具 | Agent Search、Agent Builder（ADK / Agent Engine）、Conversational Agents、Gemini Enterprise | Bedrock Knowledge Bases、Bedrock AgentCore、Amazon Quick、Amazon Lex | △ 粒度が違う |
| L6 | 開発者・運用者向け AI | （開発体験そのもの） | Gemini Code Assist、Gemini CLI、Gemini Cloud Assist | Amazon Q Developer、Kiro、CloudWatch investigations | △ 粒度が違う |

### 結論 5 行

1. **GCP は束ね、AWS は分ける。** GCP は Gemini Enterprise Agent Platform や BigQuery といった単一の器にモデル・学習・検索・生成 AI を集約する。AWS は Bedrock / SageMaker AI / OpenSearch / Redshift のように用途別サービスを並べ、必要なものを組み合わせさせる。
2. **名前が激しく変わっている。** GCP は 2026 年 4 月に **Vertex AI を Gemini Enterprise Agent Platform へ改称**。AWS は 2026 年 7 月 30 日を境に **Bedrock Agents・Q Business・Kendra の 3 製品を新規受付終了**。古い名称のまま話すと通じない。
3. **日本語対応で決定的な差がある。** 帳票 OCR の **Amazon Textract は日本語非対応**（公式明記）。**Amazon Rekognition のテキスト検出も日本語非対応**。同じ用途の GCP Document AI / Vision API は日本語に対応する。日本語文書を扱うなら、この 1 点だけで選択肢が絞られる。
4. **設計思想の差が最も大きいのは L4。** BigQuery は SQL 一つで従来型 ML もベクトル検索も生成 AI 呼び出しもこなす。AWS には「これ 1 つ」に当たるものがなく、Redshift ML・OpenSearch・Aurora pgvector・S3 Vectors を組み合わせる。
5. **AWS は第一世代の AI 製品を畳んでいる最中。** Bedrock Agents は「Classic」となり後継の AgentCore へ、Q Business は Amazon Quick へ、Kendra は Bedrock Knowledge Bases へ誘導されている。今から学ぶなら後継側を見るべき。

---

## 2. なぜ「レイヤー」で切るのか

### 切り口は「利用者が何を持ち込むか」

AI サービスを列挙するとき、分類の軸を決めないと比較が成立しない。本資料は **「利用者が何を持ち込むか」** を軸に 6 レイヤーへ分けた。

| レイヤー | 持ち込むもの | 利用者に必要なスキル |
| --- | --- | --- |
| L1 基盤モデル API | 何も持ち込まない（プロンプトだけ） | API を呼べること |
| L2 ML プラットフォーム | 自分のデータ＋自分のモデル（コード） | 機械学習の知識 |
| L3 タスク特化 API | 入力データだけ（画像・音声・文書） | API を呼べること |
| L4 データ基盤に統合された AI | 何も持ち込まない（データは既にそこにある） | SQL |
| L5 エージェント／企業内検索 | 社内データ＋道具（外部 API） | アプリ設計 |
| L6 開発者・運用者向け AI | （何も作らない。自分の作業を支援させる） | なし |

### なぜ他の軸ではだめか

- **「生成 AI か否か」で切ると L2 が浮く。** 需要予測や解約予測のような従来型の機械学習は生成 AI ではないが、AI サービスの主要な一角であり、外すと片手落ちになる。
- **「マネージド度合い」で切ると L3 と L4 が区別できない。** どちらも「呼ぶだけ」だが、L3 はデータを送りつける API、L4 はデータのある場所で動かす仕組みで、性格がまったく違う。
- **「持ち込むもの」で切ると 6 つが排他になる。** そして GCP 側と AWS 側を同じ軸で並べられる。対応表の各行が「同じ土俵の比較」であることが担保される。

### L1 と L3 の違い（混同しやすい）

どちらも「API を呼ぶだけ」だが、次の点が違う。

| | L1 基盤モデル API | L3 タスク特化 API |
| --- | --- | --- |
| モデルの用途 | 汎用。プロンプト次第で何でもやらせる | 固定。OCR なら OCR しかしない |
| 出力 | 自由なテキスト（形式は指示次第） | 構造化された固定フォーマット（座標、信頼度スコア等） |
| 精度の予測しやすさ | 低い（プロンプトに左右される） | 高い |
| 単価 | トークン量に応じて変動 | 処理量あたり定額に近い |

### 範囲外とするもの

**AI インフラ層（TPU / GPU の調達、GKE や EKS 上で自前の LLM を動かす構成）は本資料では扱わない。** ここに踏み込むと話がインフラ調達に流れ、「どんな AI サービスがあるか」という主題からずれるため。L2 の下に、こうした計算資源を直接借りる層があるとだけ認識しておけばよい。

---

## 3. L1 基盤モデル API

### レイヤーの説明

**利用者は何も持ち込まない。** クラウド事業者が学習済みの巨大モデル（LLM、画像生成、動画生成）を用意しており、API にプロンプトを投げれば結果が返る。モデルの学習も、GPU の確保も、モデルファイルの管理も不要。

生成 AI アプリを作るとき、まず触ることになるのがこのレイヤー。開発者は「モデルの上」（プロンプト設計、RAG、エージェント）に集中できる。

### GCP 側サービス

#### Gemini API

- **一言でいうと**: Google の Gemini モデルに、テキスト・画像・音声・動画を入力して結果を得る API。
- **何を解決するか**: 自前でモデルを学習・ホスティングせずに、最新の生成 AI 能力をアプリへ組み込める。入口が 2 つあり、Google AI Studio 経由（API キーだけで始められる軽量な入口）と、Gemini Enterprise Agent Platform 経由（IAM・VPC Service Controls・監査ログなど企業向けの統制が効く入口）を使い分ける。
- **典型的な使われ方**:
  - チャットボット、文章要約、分類などのテキスト生成
  - 画像や動画を入力に含むマルチモーダルな解析
  - 企業の統制下での本番運用（Agent Platform 経由）
- **課金単位**: 入力トークン数と出力トークン数（モデルごとに単価が異なる）
- **公式ドキュメント**: https://ai.google.dev/gemini-api/docs ／ 料金の考え方: https://ai.google.dev/gemini-api/docs/pricing

#### Model Garden

- **一言でいうと**: Google 自社モデルに加え、Anthropic Claude、Meta Llama、Mistral などの他社モデルを、単一のプラットフォームから選んで呼べるモデルカタログ。
- **何を解決するか**: ベンダーごとに別契約・別 API でモデルを扱う手間をなくし、統一されたガバナンスと課金のもとでモデルを使い分けられるようにする。
- **典型的な使われ方**:
  - 用途ごとに Gemini と他社モデルを使い分ける（速度重視／精度重視など）
  - Google Cloud のセキュリティ境界を保ったまま他社モデルを呼ぶ
  - オープンソースモデル（Gemma など）を自分でデプロイして検証する
- **課金単位**: 呼び出すモデルごとに異なる（多くはトークン量）。従量課金のほか、スループットを予約する方式もある
- **公式ドキュメント**: https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-garden/explore-models

#### Imagen

- **一言でいうと**: テキストから画像を生成する Google の画像生成モデル群。
- **何を解決するか**: デザイナーや画像編集ソフトを介さずに、テキスト指示だけで画像の生成・部分編集・高解像度化ができる。
- **典型的な使われ方**:
  - 広告素材やコンセプトアートの生成
  - マスクを指定した部分編集（画像の一部だけを描き替える）
  - 既存画像の高解像度化
- **課金単位**: 生成した画像の枚数（解像度や機能により単価が異なる）
- **公式ドキュメント**: https://docs.cloud.google.com/vertex-ai/generative-ai/docs/image/overview

#### Veo

- **一言でいうと**: テキストや画像から動画を生成する Google の動画生成モデル群。
- **何を解決するか**: 撮影・編集のリソースなしに短尺動画を作れる。
- **典型的な使われ方**:
  - マーケティング用の短尺動画生成
  - 静止画から動画への変換
  - 企画段階のコンセプト映像の高速作成
- **課金単位**: 生成した動画の秒数（音声の有無やモデルにより単価が異なる）
- **公式ドキュメント**: https://docs.cloud.google.com/vertex-ai/generative-ai/docs/video/overview

### AWS 側サービス

#### Amazon Bedrock

- **一言でいうと**: Amazon・Anthropic・Meta・Mistral・OpenAI など複数社の基盤モデルを、単一のマネージド API から呼べるサーバーレスのサービス。**AWS の生成 AI の入口はここに一本化されている。**
- **何を解決するか**: モデルごとに異なるインフラや SDK を個別に管理せずに済み、コードをほぼ変えずにモデルを差し替えられる。RAG（Knowledge Bases）、エージェント（AgentCore）、安全性フィルタ（Guardrails）といった周辺機能も同じサービスの中で提供される。
- **典型的な使われ方**:
  - Claude や Nova を共通インターフェース（Converse API / Invoke API）で呼ぶ
  - Knowledge Bases と組み合わせて RAG を構築する
  - Guardrails で不適切な入出力をフィルタする
- **課金単位**: 標準は入力／出力トークン数。ほかにバッチ推論（割安）、スループット予約、複数のサービス階層（Standard / Priority / Flex / Reserved）がある
- **公式ドキュメント**: https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html ／ 製品ページ: https://aws.amazon.com/bedrock/

#### Amazon Nova

- **一言でいうと**: AWS 自社開発の基盤モデルファミリー。Bedrock 上でのみ提供される。
- **何を解決するか**: 他社モデルに依存せず、低コスト・低レイテンシで AWS ネイティブなモデルを使いたいというニーズに応える。
- **典型的な使われ方**:
  - Nova Micro / Lite / Pro / Premier をコストと精度のバランスで使い分ける
  - Nova Sonic による音声対話
  - Nova Canvas（画像生成）、Nova Reel（動画生成）
- **課金単位**: テキスト系はトークン数。画像・動画系は生成物の量
- **公式ドキュメント**: https://aws.amazon.com/nova/
- **注意**: **Nova Canvas と Nova Reel は終息予定。** 公式モデルカードに `Model EOL date: September 30, 2026`、`Model lifecycle: Legacy (certain regions)` と明記されている（https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-nova-canvas.html ）。AWS の画像・動画生成は自社モデルではなく Bedrock 上の他社モデルへ寄せる方向にある。

### GCP ↔ AWS 対応表（L1）

| GCP | AWS 相当 | 精度 | ズレの中身 |
| --- | --- | --- | --- |
| Gemini API（Agent Platform 経由） | Amazon Bedrock（Amazon Nova 呼び出し） | ◎ ほぼ同等 | どちらも「自社の企業向け基盤の上で、自社モデルを IAM 等と統合して呼ぶ」構図で一致する |
| Model Garden | Amazon Bedrock（他社モデルカタログ全体） | ◎ ほぼ同等 | 複数社モデルを単一 API で束ねる思想は同じ。違いは階層で、GCP は Model Garden をエージェント基盤の一機能として位置づけ、AWS は Bedrock 自体がその役割を担う |
| Imagen | Amazon Nova Canvas ／ Bedrock 上の他社画像モデル | △ 粒度が違う | Imagen は主力製品として強化が続くが、Nova Canvas は 2026-09-30 で EOL。AWS は自社画像モデルから撤退方向で、力の入れ方が対照的 |
| Veo | Amazon Nova Reel ／ Bedrock 上の他社動画モデル | △ 粒度が違う | 同上。Nova Reel も 2026-09-30 で EOL |
| Google AI Studio（API キーだけで使える軽量な入口） | 相当なし | ✕ 相当なし | Bedrock は AWS アカウント前提のマネージドサービスとして統一されており、「無料・APIキーのみ」の軽量な入口という概念がない |

### このレイヤーの設計思想の違い

GCP は入口を分けている。**軽く始める入口（Google AI Studio）**と**統制の効く本番向けの入口（Gemini Enterprise Agent Platform）**を意図的に分離し、フェーズによって使い分けさせる。対して AWS は Bedrock という単一サービスの中に自社モデル（Nova）と他社モデルをフラットに並べ、入口を分けない設計で一貫している。

もう一つの差は自社モデルへの投資姿勢。GCP は Imagen / Veo を主力として強化し続けている一方、AWS は自社の画像・動画モデルを EOL にして他社モデルへ集約しつつある。**AWS は「モデルの品揃えを提供する場」であることを重視し、GCP は「自社モデルの性能」で戦っている**、と読める。

### このレイヤーの未確認事項

- Imagen / Veo の具体的な単価。公式料金ページの該当セクションを取得しきれなかった。
- Nova Canvas / Nova Reel の後継として案内されている具体的なモデル名（EOL 日付自体は公式モデルカードで確認済み）。

---

## 4. L2 ML プラットフォーム

### レイヤーの説明

**利用者は自分のデータと、自分で書いたモデルのコードを持ち込む。** データの前処理・学習・評価・デプロイ・監視という一連の流れ（MLOps）を、マネージドな基盤の上で回すためのレイヤー。

L1 が「できあいのモデルを呼ぶ」のに対し、ここは **「モデルを作る側・運用する側」の作業そのもの**が対象になる。主な利用者はデータサイエンティストや ML エンジニアで、需要予測・解約予測・レコメンドといった、自社データに固有のモデルを本番運用したいときに使う。生成 AI ブーム以前から存在する、AI サービスの土台にあたる層。

> **重要な注意**: このレイヤーは両クラウドとも 2024〜2026 年に上位ブランドの改称が起きている。GCP は **Vertex AI → Gemini Enterprise Agent Platform**、AWS は **Amazon SageMaker → Amazon SageMaker AI**。機能自体は存続しており、名前と位置づけが変わっただけである。

### GCP 側サービス

GCP のこのレイヤーは、**Gemini Enterprise Agent Platform（旧 Vertex AI）の `machine-learning` 配下の機能群**として提供される。

#### Vertex AI Training（カスタム学習）

- **一言でいうと**: 自分のデータと学習コード（PyTorch / TensorFlow など）を持ち込み、マネージドな基盤で分散学習まで実行する機能。
- **何を解決するか**: GPU / TPU クラスタの構築・管理をせずに、大規模データでの学習やハイパーパラメータ探索ができる。
- **典型的な使われ方**:
  - スクリプトやコンテナを投入しての分散学習
  - ハイパーパラメータチューニングジョブによる自動探索
  - コードを書かずに済ませたい場合は AutoML へ切り替える
- **課金単位**: 使用したマシンタイプ（vCPU / メモリ / GPU / TPU）× 学習時間
- **公式ドキュメント**: https://docs.cloud.google.com/gemini-enterprise-agent-platform/machine-learning/training-overview

#### Vertex AI Prediction / Endpoints（推論エンドポイント）

- **一言でいうと**: 学習済みモデルを、オンライン（リアルタイム）またはバッチの推論エンドポイントとして公開する機能。
- **何を解決するか**: 本番トラフィックへの低レイテンシな予測提供と、スケーリング・モデル切り替えの運用負荷を下げる。
- **典型的な使われ方**:
  - エンドポイントへのモデルデプロイとオートスケーリング
  - Cloud Storage / BigQuery を入出力にしたバッチ推論
- **課金単位**: **デプロイしたノードの起動時間。リクエストが 1 件も来なくても、デプロイしている間は課金され続ける**（この点は L1 のトークン課金と決定的に違う）
- **公式ドキュメント**: https://docs.cloud.google.com/gemini-enterprise-agent-platform/machine-learning/start/predictions-guide

#### Vertex AI Pipelines

- **一言でいうと**: 前処理 → 学習 → 評価 → デプロイという一連の流れを自動化する、サーバーレスのワークフロー基盤。
- **何を解決するか**: 手順をつないで再現可能にし、誰が実行しても同じ結果になるようにする。実行履歴とデータの来歴（リネージ）も追跡できる。
- **典型的な使われ方**:
  - 学習から評価、条件分岐、モデル登録までのパイプライン定義
  - スケジュール実行による定期的なモデル再学習
- **課金単位**: パイプライン実行の管理コスト＋内部で呼び出す学習・推論の実費
- **公式ドキュメント**: https://docs.cloud.google.com/gemini-enterprise-agent-platform/machine-learning/pipelines/introduction

#### Vertex AI Model Registry

- **一言でいうと**: 学習済みモデルのバージョンとメタデータを一元管理する中央リポジトリ。
- **何を解決するか**: 繰り返し学習したモデルの版管理と、「どのバージョンをどのエンドポイントにデプロイしたか」の追跡。
- **典型的な使われ方**:
  - カスタムモデル・AutoML モデル・BigQuery ML モデルの登録
  - エイリアスやラベルによる「本番用」「検証用」の区別
- **課金単位**: レジストリ自体への追加料金はなく、モデルファイルの Cloud Storage 保存料のみ
- **公式ドキュメント**: https://docs.cloud.google.com/gemini-enterprise-agent-platform/machine-learning/model-registry/introduction

**その他（各 1 行）**

- **Feature Store**: 特徴量を BigQuery のテーブル／ビュー上で一元管理し、低レイテンシで配信するメタデータ層。 https://docs.cloud.google.com/gemini-enterprise-agent-platform/machine-learning/featurestore/latest/overview
- **AutoML**: 学習データを与えるだけで、コードなしにモデルを構築できる機能。 https://docs.cloud.google.com/gemini-enterprise-agent-platform/machine-learning/training/automl-training-overview

### AWS 側サービス

AWS のこのレイヤーは **Amazon SageMaker AI**（旧 Amazon SageMaker）。2024 年 12 月に改称され、上位に「データ・分析・AI の統合基盤」としての新しい Amazon SageMaker が置かれた。**API 名前空間・CLI・IAM ポリシー・CloudFormation リソース名は後方互換のため変更されていない。**

#### SageMaker AI Training Jobs

- **一言でいうと**: コンテナベースで学習インフラの起動・管理を肩代わりする、フルマネージドな学習サービス。
- **何を解決するか**: 学習用インスタンスの調達や分散学習の構成を自前で組まずに、モデル開発に集中できる。
- **典型的な使われ方**:
  - 組み込みアルゴリズム（XGBoost など）や JumpStart の学習済みモデルを SDK から学習
  - 独自コンテナ持ち込みによる大規模分散学習
  - スポットインスタンス活用によるコスト最適化
- **課金単位**: 選択したインスタンスタイプ × 使用時間
- **公式ドキュメント**: https://docs.aws.amazon.com/sagemaker/latest/dg/how-it-works-training.html

#### SageMaker AI Inference Endpoints

- **一言でいうと**: 学習済みモデルを、リアルタイム／サーバーレス／非同期の 3 方式でホスティングする機能。
- **何を解決するか**: トラフィックの性質（常時か間欠か、応答が速いべきか長時間処理か）に応じて最適な配信形態を選べる。
- **典型的な使われ方**:
  - リアルタイムエンドポイント: 低レイテンシが必要な常時稼働ワークロード
  - サーバーレス推論: トラフィックが間欠的で、起動の遅れを許容できる場合
  - 非同期推論: 大きな入力データや長時間の処理をキューに積む場合
- **課金単位**: リアルタイムはインスタンス時間。**サーバーレス推論はミリ秒単位の処理時間＋処理データ量**（ここが GCP の Prediction と違い、アイドル時に課金されない選択肢がある）
- **公式ドキュメント**: https://docs.aws.amazon.com/sagemaker/latest/dg/deploy-model.html

#### SageMaker AI Pipelines

- **一言でいうと**: ML ワークフローを自動化するオーケストレーションサービス。
- **何を解決するか**: オーケストレーション基盤自体を運用せずに、GUI・SDK・API のいずれでもパイプラインを組める。
- **典型的な使われ方**:
  - SageMaker Studio のドラッグ＆ドロップによるパイプライン作成
  - Python SDK によるコードでのワークフロー定義
- **課金単位**: オーケストレーション自体への追加課金はなく、呼び出す学習・推論の実費のみ
- **公式ドキュメント**: https://docs.aws.amazon.com/sagemaker/latest/dg/pipelines.html

#### SageMaker AI Model Registry

- **一言でいうと**: 本番投入するモデルのバージョン・メタデータ・**承認ステータス**を管理するカタログ。
- **何を解決するか**: どのモデルがどの段階（検証中／承認済み）にあるかを追跡し、CI/CD による自動デプロイにつなげる。
- **典型的な使われ方**:
  - パイプライン実行のたびに新バージョンとして登録
  - 承認ステータスをトリガーにした自動デプロイ
- **課金単位**: レジストリ自体への追加課金はなく、S3 の保存料が実質のコスト
- **公式ドキュメント**: https://docs.aws.amazon.com/sagemaker/latest/dg/model-registry.html

**その他（各 1 行）**

- **Feature Store**: 特徴量を feature group として管理し、オンラインストア（低レイテンシ）とオフラインストア（S3 上の Parquet）を使い分ける。 https://docs.aws.amazon.com/sagemaker/latest/dg/feature-store.html
- **Studio**: JupyterLab / Code Editor などを統合し、学習ジョブやエンドポイントを 1 つの UI から横断的に扱う Web IDE。 https://docs.aws.amazon.com/sagemaker/latest/dg/studio-updated.html
- **Canvas**: コードを書かずにデータ取り込みからモデル構築・予測までできるノーコードツール。 https://docs.aws.amazon.com/sagemaker/latest/dg/canvas.html

### GCP ↔ AWS 対応表（L2）

| GCP | AWS 相当 | 精度 | ズレの中身 |
| --- | --- | --- | --- |
| Vertex AI Training | SageMaker AI Training Jobs | ◎ ほぼ同等 | どちらもコンテナベースの分散学習。独自コンテナの持ち込みも両方できる |
| Vertex AI Prediction / Endpoints | SageMaker AI Inference Endpoints | ◎ ほぼ同等 | リアルタイム／バッチ／非同期の構成が対応する。AWS 側にはミリ秒課金のサーバーレス推論があり、間欠的なトラフィックでのコスト構造が異なる |
| Vertex AI Pipelines | SageMaker AI Pipelines | ◎ ほぼ同等 | どちらもサーバーレス。AWS は Studio 統合のビジュアルエディタが強み |
| Vertex AI Model Registry | SageMaker AI Model Registry | ◎ ほぼ同等 | バージョン管理・承認ステータス・CI/CD 連携という考え方が一致する |
| Vertex AI Feature Store | SageMaker AI Feature Store | △ 粒度が違う | GCP は BigQuery のテーブルをそのままオフラインストアとして扱う「メタデータ層」方式。AWS は専用のオンライン／オフラインストアを持つ独立コンポーネント。**データをどこに置くかの思想が違う** |
| Vertex AI Workbench | SageMaker AI Studio | △ 粒度が違う | GCP の Workbench はノートブック環境が主眼。AWS の Studio はパイプライン管理やエンドポイント監視まで含む統合 IDE で、カバー範囲が広い |
| AutoML | SageMaker AI Canvas | △ 粒度が違う | GCP の AutoML は開発者が API / コンソールから使う機能。AWS の Canvas はビジネスアナリスト向けのノーコード UI として独立製品化されている。**想定利用者が違う** |

### このレイヤーの設計思想の違い

興味深いことに、**両社ともほぼ同時期に「ML サービスを上位ブランドの傘下に入れる」再編を行っている。** GCP は 2026 年 4 月に Vertex AI を Gemini Enterprise Agent Platform に改称し、ML 機能をその配下に置いた。AWS は 2024 年 12 月に SageMaker を SageMaker AI に改称し、上位に統合基盤としての新 SageMaker を置いた。**どちらも「単体の ML サービス」から「より広い基盤の一部」へと位置づけを変えている**わけで、生成 AI とエージェントが主役になったことの表れと読める。

個々の機能では、GCP は BigQuery との結合を前提に Feature Store を設計し直すなどデータウェアハウス統合を志向する。AWS は S3 ベースのオフラインストアと低遅延オンラインストアを明確に分離する設計を保っている。ここでも「束ねる GCP、分ける AWS」の構図が出ている。

### このレイヤーの未確認事項

- 改称に伴い、Vertex AI SDK / API の名前空間（`aiplatform` など）が将来変更される予定があるかどうか。
- 両クラウドの具体的な単価。公式料金ページの本文を取得しきれなかった。

---

## 5. L3 タスク特化 API

### レイヤーの説明

**利用者は入力データだけを持ち込む。** 用途があらかじめ固定された学習済みモデル（OCR、音声認識、翻訳、画像認識）に、画像・音声・テキストを投げれば結果が返る。モデルの学習は不要。

L1 の基盤モデルとの違いは 2 章で述べたとおりで、**出力形式が固定されている**点が最大の特徴。座標つきの検出結果や信頼度スコアなど、構造化されたデータが決まった形で返るため、後続の処理を書きやすい。

> **このレイヤーは日本語対応を必ず確認すること。** 後述するとおり、AWS 側には日本語非対応のサービスがある。

### GCP 側サービス

#### Document AI

- **一言でいうと**: 帳票・契約書などの非構造化文書を、構造化データに変換するプラットフォーム。
- **何を解決するか**: 請求書や領収書から「日付」「金額」「取引先名」といった項目を、レイアウトごと理解した上で抽出する。単純な文字起こし（OCR）と違い、文書の構造と意味を解釈する。
- **典型的な使われ方**:
  - 経理業務における請求書・領収書のデータ入力自動化
  - 契約書管理（契約日・当事者名の自動抽出）
  - 業種特化文書のカスタム抽出（Custom Extractor）
- **日本語対応**: **対応**。Enterprise Document OCR、Form Parser、Layout Parser、Expense Parser、Custom Extractor が日本語に対応する。ただし Bank Statement Parser や W2 Parser など米国の制度に特化したプロセッサは英語のみ。
- **課金単位**: 処理したページ数（プロセッサの種類により単価が異なる）
- **公式ドキュメント**: https://docs.cloud.google.com/document-ai/docs/overview ／ 対応言語: https://docs.cloud.google.com/document-ai/docs/languages

#### Cloud Speech-to-Text

- **一言でいうと**: 音声データをテキストに変換する API。
- **何を解決するか**: 通話記録、会議音声、動画字幕などを、人手を介さずテキスト化する。
- **典型的な使われ方**:
  - コールセンター通話のリアルタイム／バッチ文字起こし
  - 会議・講演の議事録自動生成
  - 電話音声向けの専用モデルを使った通話システム連携
- **日本語対応**: **対応**（`ja-JP`）。句読点の自動挿入、話者分離、単語単位の信頼度といった主要機能も日本語で使える。
- **課金単位**: 音声の長さ（分・秒）
- **公式ドキュメント**: https://docs.cloud.google.com/speech-to-text/docs ／ 対応言語: https://docs.cloud.google.com/speech-to-text/docs/languages

#### Cloud Vision API

- **一言でいうと**: 画像に対する OCR・物体検出・ラベル検出などをまとめて提供する API。
- **何を解決するか**: 画像内のテキスト抽出、物体やシーンの認識、不適切コンテンツの検出を、モデル学習なしで実行できる。
- **典型的な使われ方**:
  - 画像内テキストの抽出（看板、書類の写真など）
  - ラベル検出による画像の自動タグ付け
  - 不適切コンテンツの自動フィルタリング
- **日本語対応**: **対応**（`ja` / スクリプト `Jpan`）。言語ヒントを明示しなくても自動検出される。
- **課金単位**: 画像 1 枚 × 適用した機能ごとのユニット（同じ画像に複数機能を適用すると機能数分課金される）
- **公式ドキュメント**: https://docs.cloud.google.com/vision/docs ／ 対応言語: https://docs.cloud.google.com/vision/docs/languages

#### Cloud Translation API

- **一言でいうと**: テキストを言語間で機械翻訳する API。
- **何を解決するか**: 翻訳エンジンを自前で持たずに、アプリから翻訳を呼び出せるようにする。
- **典型的な使われ方**:
  - Web サイト・UI の多言語化
  - カスタマーサポート文面のリアルタイム翻訳
  - 大量文書のバッチ翻訳
- **日本語対応**: **対応**。用語集（グロッサリー）を使った訳語の統一もできる。
- **課金単位**: 翻訳した文字数（空白・改行・HTML タグも文字数に含まれる点に注意）
- **公式ドキュメント**: https://docs.cloud.google.com/translate/docs

**その他（各 1 行）**

- **Cloud Text-to-Speech**: 日本語のニューラル音声を含む音声合成 API。 https://docs.cloud.google.com/text-to-speech/docs
- **Cloud Natural Language API**: 日本語を含む主要言語のエンティティ抽出・感情分析を行うテキスト解析 API。 https://docs.cloud.google.com/natural-language/docs
- **Video Intelligence API**: 映像内の物体・シーン検出を行う。内蔵の音声文字起こしは英語のみで、日本語音声は Speech-to-Text との併用が必要。 https://docs.cloud.google.com/video-intelligence/docs

### AWS 側サービス

#### Amazon Textract

- **一言でいうと**: 文書画像や PDF からテキスト・表・フォーム項目を抽出する OCR / 文書解析 API。
- **何を解決するか**: 請求書や申込書から、手書きを含むテキスト、表構造、キーと値のペアを抽出する。
- **典型的な使われ方**:
  - 請求書・領収書からの金額・取引先データ抽出（AnalyzeExpense）
  - フォーム・申込書のキー・バリュー抽出
  - 身分証明書の読み取り（AnalyzeID）
- **日本語対応**: **非対応。** 公式ドキュメントに "Amazon Textract supports English, Spanish, German, Italian, French, and Portuguese" と明記されており、日本語は対応言語に含まれない。
- **課金単位**: 処理したページ数（API の種類により単価が異なる）
- **公式ドキュメント**: https://docs.aws.amazon.com/textract/latest/dg/what-is.html ／ 言語制限の明記: https://docs.aws.amazon.com/textract/latest/dg/textract-best-practices.html

#### Amazon Transcribe

- **一言でいうと**: 音声データをテキストに変換する API。
- **何を解決するか**: 通話や会議の音声を自動でテキスト化し、検索・分析・議事録作成につなげる。
- **典型的な使われ方**:
  - コールセンター通話のバッチ／リアルタイム文字起こし
  - Call Analytics による通話内容の要約
  - カスタム語彙を用いた専門用語の認識精度向上
- **日本語対応**: **対応**（`ja-JP`）。バッチ・ストリーミングの両方に対応し、カスタム言語モデルも日本語で使える。ただし **PII（個人情報）の自動秘匿機能は日本語未対応**。
- **課金単位**: 音声の長さ（秒単位。1 リクエストあたり最低 15 秒）
- **公式ドキュメント**: https://docs.aws.amazon.com/transcribe/latest/dg/what-is.html ／ 対応言語: https://docs.aws.amazon.com/transcribe/latest/dg/supported-languages.html

#### Amazon Rekognition

- **一言でいうと**: 画像・動画に対する物体検出・顔認識・テキスト検出などを提供する API。
- **何を解決するか**: 画像や動画の中の物体・顔・不適切コンテンツ・テキストを検出し、メディア検索や本人確認、モデレーションを実現する。
- **典型的な使われ方**:
  - 顔認証による本人確認
  - 不適切コンテンツの自動検出
  - 画像内テキストの検出（DetectText）
- **日本語対応**: **テキスト検出（DetectText）は非対応。** 対応言語は英語・アラビア語・ロシア語・ドイツ語・フランス語・イタリア語・ポルトガル語・スペイン語の 8 言語で、日本語は含まれない。なお顔検出や物体検出など言語に依存しない機能は日本語圏の画像でも問題なく使える。
- **課金単位**: 画像は処理枚数、動画は処理分数
- **公式ドキュメント**: https://docs.aws.amazon.com/rekognition/latest/dg/what-is.html

#### Amazon Translate

- **一言でいうと**: テキストを言語間で機械翻訳する API。
- **何を解決するか**: 自前の翻訳エンジンなしに、アプリから翻訳を呼び出せるようにする。
- **典型的な使われ方**:
  - Web コンテンツ・UI の多言語化
  - チャットサポートのリアルタイム翻訳
  - ドキュメントのバッチ翻訳
- **日本語対応**: **対応**。リアルタイム翻訳・バッチ翻訳の双方で使える。
- **課金単位**: 翻訳した文字数
- **公式ドキュメント**: https://docs.aws.amazon.com/translate/latest/dg/what-is.html

**その他（各 1 行）**

- **Amazon Comprehend**: 日本語を含む言語で感情分析・エンティティ抽出を行うテキスト解析。課金は 100 文字を 1 ユニットとする単位。 https://docs.aws.amazon.com/comprehend/latest/dg/what-is.html
- **Amazon Polly**: 音声合成。日本語のニューラル音声も提供される。課金は文字数。 https://docs.aws.amazon.com/polly/latest/dg/what-is.html

### GCP ↔ AWS 対応表（L3）

| GCP | AWS 相当 | 精度 | ズレの中身 |
| --- | --- | --- | --- |
| Document AI | Amazon Textract | △ 粒度が違う | **最大のズレは日本語対応の有無。** Document AI は日本語の帳票 OCR・フォーム解析に対応するが、**Textract は日本語非対応**。加えて Document AI は業種特化パーサーが豊富、Textract は米国制度に特化したパーサーが中心で、対象文書の傾向自体が違う |
| Cloud Speech-to-Text | Amazon Transcribe | ◎ ほぼ同等 | どちらも `ja-JP` でバッチ・ストリーミング両対応。Transcribe は PII 秘匿が日本語未対応という差はある |
| Cloud Vision API | Amazon Rekognition | △ 粒度が違う | 物体検出・顔検出・モデレーションは同等。ただし **テキスト検出に限ると Vision API は日本語対応、Rekognition は日本語非対応**。日本語画像 OCR では Rekognition は選択肢にならない |
| Cloud Translation API | Amazon Translate | ◎ ほぼ同等 | どちらも日本語対応。用語集など高度なカスタマイズの粒度に差がある程度 |
| Cloud Natural Language API | Amazon Comprehend | ◎ ほぼ同等 | どちらも日本語の感情分析・エンティティ抽出に対応。課金単位（文字数 vs 100 文字ユニット）が違う |
| Cloud Text-to-Speech | Amazon Polly | ◎ ほぼ同等 | どちらも日本語のニューラル音声を提供。声の種類数やチューニングの粒度が違う |
| Video Intelligence API | Amazon Rekognition Video | △ 粒度が違う | 映像内の物体・シーン検出は両者対応。ただし GCP 側は内蔵の音声文字起こしが英語限定で、日本語音声は Speech-to-Text との併用が必要 |

### 生成 AI による代替の動き

このレイヤーは、L1 の基盤モデルに侵食されつつある。Gemini や Bedrock 上の Claude / Nova はマルチモーダル対応なので、画像・音声・文書をそのまま理解できる。**「日本語の手書き文書」「非定型フォーマットの契約書」のように、あらかじめ決まったスキーマに収まらない文書処理では、専用パーサーをチューニングするより、基盤モデルにプロンプトで構造化 JSON を出力させる方が開発が速い**ケースが増えている。

一方で、タスク特化 API が依然有利な領域も明確にある。使い分けの指針は次のとおり。

| 条件 | 選ぶべきレイヤー | 理由 |
| --- | --- | --- |
| 同一フォーマットの帳票を毎日数万件処理する | L3 タスク特化 API | 単価が安定して安く、出力フォーマットが崩れない |
| リアルタイム音声認識で低遅延が要る | L3 タスク特化 API | ストリーミング処理に最適化されている |
| 非定型文書から、都度違う項目を抜きたい | L1 基盤モデル | プロンプトを変えるだけで対応でき、開発が速い |
| 抽出した内容の要約・判断まで一気にやりたい | L1 基盤モデル | 抽出と推論を 1 回の呼び出しで完結できる |

### このレイヤーの設計思想の違い

GCP は「1 つのサービスに複数のプロセッサ／機能を内包させ、同一 API のオプション指定で挙動を切り替える」。AWS は「Textract、Rekognition、Comprehend のように機能ごとにサービスを分割し、その中でも API オペレーションを細分化する」。

この違いは日本語対応のばらつきにも表れている。GCP は汎用エンジン（Document AI の OCR、Vision API）が広範な言語をカバーし、米国特化の個別プロセッサだけが英語限定。AWS はサービスごとに個別に言語を追加してきた経緯があり、**日本語対応が「サービス単位で対応済み／非対応にはっきり分かれる」**状態になっている。

### このレイヤーの未確認事項

- Document AI / Cloud Translation API のプロセッサ別の詳細単価。公式料金ページの本文を取得しきれなかった。
- Video Intelligence API の内蔵音声文字起こしが 2026 年 7 月時点でも英語限定のままか（直近のリリースノートまでは未確認）。
- Textract と Rekognition の日本語非対応は今後のアップデートで変わる可能性がある。導入判断の際は必ず最新の対応言語ページを再確認すること。

---

## 6. L4 データ基盤に統合された AI

### レイヤーの説明

**データを動かさない。** データウェアハウス（BigQuery / Redshift）や通常のデータベース（AlloyDB / Cloud SQL / Aurora）が既に持っているデータに対して、その場で機械学習やベクトル検索を実行する仕組み。

なぜデータを動かさないことが重要か。理由は 2 つある。

1. **ETL パイプラインの構築・保守コストが消える。** 「DWH からデータを抜いて、ML 基盤へ転送して、学習して、結果を書き戻す」という配管が不要になる。
2. **権限管理が一箇所で済む。** データが元の場所にとどまるので、IAM や行レベルセキュリティといった既存のガバナンスがそのまま効く。データのコピーが増えるほど、統制は難しくなる。

**このレイヤーは 6 つの中で GCP と AWS の設計思想の差が最も大きい。**

### GCP 側サービス

#### BigQuery ML

- **一言でいうと**: BigQuery のテーブルに対して、SQL（`CREATE MODEL` など）だけでモデルの学習・評価・推論を完結させる機能。
- **何を解決するか**: データを BigQuery の外へ出さずに機械学習ができる。しかも従来型の統計モデル（回帰・分類・クラスタリング・時系列予測）と、**リモートモデル経由での Gemini など生成 AI の呼び出し**の両方を、同じ SQL の中で扱える。
- **典型的な使われ方**:
  - 線形回帰・ロジスティック回帰による解約予測、需要予測
  - K-means による顧客セグメンテーション
  - `AI.GENERATE_TEXT` で Gemini を呼び、SQL の結果セットに対して要約や分類を適用する
- **課金単位**: 学習・推論クエリは BigQuery のスキャンバイト量またはスロット（計算資源）。モデル自体のストレージ料金。生成 AI のリモートモデル呼び出しは別途トークン量で課金される
- **公式ドキュメント**: https://docs.cloud.google.com/bigquery/docs/bqml-introduction ／ 生成 AI 連携: https://docs.cloud.google.com/bigquery/docs/generative-ai-overview

#### BigQuery のベクトル検索

- **一言でいうと**: BigQuery のテーブル列に格納した埋め込みベクトルに対して、SQL の `VECTOR_SEARCH` 関数で近似最近傍検索を行う機能。
- **何を解決するか**: 別のベクトルデータベースへ埋め込みをコピーせずに、DWH 内のデータへ直接セマンティック検索や RAG を実行できる。
- **典型的な使われ方**:
  - RAG（文書を検索して、その内容をもとに回答を生成する）
  - 商品レコメンド、ログの異常検知
  - 表記ゆれのある住所・顧客レコードの名寄せ
- **課金単位**: 検索クエリはスキャンバイト量またはスロット使用量。埋め込みとインデックスのストレージ料金
- **公式ドキュメント**: https://docs.cloud.google.com/bigquery/docs/vector-search-intro ／ インデックス: https://docs.cloud.google.com/bigquery/docs/vector-index

#### Vertex AI Vector Search（旧 Matching Engine）

- **一言でいうと**: 数十億規模のベクトルに対して、低レイテンシで近似最近傍検索を行う専用のマネージドサービス。
- **何を解決するか**: BigQuery のベクトル検索がバッチ的な用途に向くのに対し、こちらはインデックスをエンドポイントにデプロイして、**オンラインでサブ秒応答**を大規模・高スループットで提供する。
- **典型的な使われ方**:
  - EC サイトのリアルタイム商品レコメンド
  - チャットボット・エージェントの RAG 基盤
  - 画像とテキストを横断するマルチモーダル検索
- **課金単位**: インデックスをホストするノードの稼働時間＋インデックス構築・更新の処理コスト
- **公式ドキュメント**: https://docs.cloud.google.com/vertex-ai/docs/vector-search/overview

#### AlloyDB AI ／ Cloud SQL の pgvector

- **一言でいうと**: PostgreSQL 互換のデータベースに、標準の pgvector 拡張と Google 独自の高速インデックスを統合したベクトル検索機能。
- **何を解決するか**: 業務データ（注文履歴など）と埋め込みベクトルを同じデータベースに同居させ、別途ベクトル DB を持たずに RAG やセマンティック検索を実現する。
- **典型的な使われ方**:
  - 業務データと紐づいたセマンティック検索
  - データベースの拡張機能から直接、埋め込み生成や要約などの AI 関数を呼ぶ
  - フィルタ条件つきのベクトル検索（「東京都の商品に限定して類似検索」など）
- **課金単位**: ベクトル検索固有の追加課金はなく、インスタンスの計算資源とストレージの通常課金に含まれる
- **公式ドキュメント**: https://docs.cloud.google.com/alloydb/docs/ai/vector-search-overview

### AWS 側サービス

#### Amazon Redshift ML

- **一言でいうと**: `CREATE MODEL` という SQL 文で、Redshift の中から SageMaker AI のモデル学習・呼び出しを行う機能。
- **何を解決するか**: データをエクスポートせずに Redshift 内のデータで学習し、推論は Redshift クラスタ内でローカル実行できる（推論自体には追加課金がない）。別系統のインターフェースとして `CREATE EXTERNAL MODEL ... MODEL_TYPE BEDROCK` を使うと、Bedrock 上の生成 AI モデルを SQL から直接呼べる。
- **典型的な使われ方**:
  - 解約予測、不正検知、需要予測などの教師あり学習
  - 外部で学習済みの SageMaker モデルをインポートしてローカル推論
  - Bedrock 連携による要約・翻訳・感情分析
- **課金単位**: 学習は処理した「セル数」（行 × 列）に応じた階層課金＋ SageMaker の学習ジョブ費用。ローカル推論には追加課金なし。Bedrock 連携は Bedrock 側のトークン課金が別途発生
- **公式ドキュメント**: https://docs.aws.amazon.com/redshift/latest/dg/machine_learning_overview.html ／ Bedrock 連携: https://docs.aws.amazon.com/redshift/latest/dg/machine-learning-br.html

#### Amazon OpenSearch Service のベクトル検索

- **一言でいうと**: OpenSearch の k-NN 機能によるベクトル類似検索。マネージド版とサーバーレス版の両方がある。
- **何を解決するか**: 全文検索・フィルタ・集計といった検索エンジンの機能と、ベクトル類似検索を 1 つのインデックスで組み合わせられる（ハイブリッド検索）。
- **典型的な使われ方**:
  - 画像検索、文書検索、商品レコメンド
  - 生成 AI アプリのナレッジベース
  - キーワード一致とセマンティック検索を併用した検索精度の向上
- **課金単位**: マネージド版はインスタンスとストレージ。サーバーレス版は OCU（OpenSearch Compute Unit）の稼働量
- **公式ドキュメント**: https://docs.aws.amazon.com/opensearch-service/latest/developerguide/knn.html ／ サーバーレス: https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless-vector-search.html

#### Amazon Aurora PostgreSQL の pgvector

- **一言でいうと**: Aurora PostgreSQL に標準の pgvector 拡張を入れて、ベクトルの格納と類似検索を行う機能。
- **何を解決するか**: 業務データと埋め込みを同じクラスタに同居させる。Bedrock Knowledge Bases の RAG 用ベクトルストアとしても指定できる。
- **典型的な使われ方**:
  - Bedrock Knowledge Bases のベクトルストアとして利用
  - 業務データと組み合わせたセマンティック検索
- **課金単位**: pgvector 固有の追加課金はなく、Aurora の通常課金に含まれる
- **公式ドキュメント**: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraPostgreSQL.VectorDB.html

#### Amazon S3 Vectors

- **一言でいうと**: オブジェクトストレージである S3 自体に、ベクトルの保存とクエリをネイティブ対応させた機能。
- **何を解決するか**: 専用のベクトル DB を構築せずに、大量のベクトルを低コストで長期保存・検索できるようにする。
- **典型的な使われ方**:
  - Bedrock Knowledge Bases の RAG 用ベクトルストア（低コスト層として）
  - アクセス頻度で使い分ける階層構成（高頻度は OpenSearch、低頻度は S3 Vectors）
  - 長期保管が必要な大量データのセマンティック検索
- **課金単位**: 使用量ベース（ベクトルのアップロード・保存・クエリ量に応じた従量課金）
- **公式ドキュメント**: https://aws.amazon.com/s3/features/vectors/
- **注意**: 非常に新しいサービスのため、仕様変更の可能性がある。

### GCP ↔ AWS 対応表（L4）

| GCP | AWS 相当 | 精度 | ズレの中身 |
| --- | --- | --- | --- |
| BigQuery ML | Amazon Redshift ML | △ 粒度が違う | SQL で DWH 内学習・推論をする点は同じ。ただし **BigQuery ML は従来型モデルと生成 AI 呼び出しを統一的な SQL 体験の中に持つ**のに対し、Redshift ML は従来型 ML が中核で、生成 AI 呼び出しは `CREATE EXTERNAL MODEL` という別系統として後から追加された。課金の考え方（スキャン量 vs セル数）も違う |
| BigQuery のベクトル検索 | **Redshift にネイティブな相当機能なし** | ✕ 相当なし | Redshift はベクトル型・ベクトルインデックスをネイティブに持たない。**「データウェアハウス自体にベクトル検索が組み込まれている」のは GCP 側の特徴**。AWS で近いことをするなら OpenSearch や Aurora pgvector という別サービスを組み合わせる |
| Vertex AI Vector Search | Amazon OpenSearch Service のベクトル検索 | ◎ ほぼ同等 | どちらも大規模・低レイテンシの専用検索基盤。用途（RAG、レコメンド）も課金の考え方（ノード／OCU の稼働時間）も近い |
| AlloyDB AI ／ Cloud SQL pgvector | Amazon Aurora PostgreSQL pgvector | ◎ ほぼ同等 | どちらも標準 pgvector ベースで OLTP DB に埋め込みを同居させる設計。差は GCP 側に独自の高速インデックスがある点 |
| **相当なし** | Amazon S3 Vectors | ✕ 相当なし | オブジェクトストレージ自体にベクトルインデックスを持たせるという新しいカテゴリ。Cloud Storage に同等の機能は確認できなかった |

### このレイヤーの設計思想の違い

**GCP は BigQuery という単一の器にすべてを入れる。** 従来型 ML（BigQuery ML）、ベクトル検索（`VECTOR_SEARCH`）、生成 AI 呼び出し（`AI.GENERATE_TEXT`）が、同じ SQL 方言・同じ課金体系の中に統合されている。学ぶべきものが SQL だけで済み、「BigQuery を見ればほぼ完結する」。

**AWS は用途別に専門特化させ、組み合わせさせる。** DWH（Redshift）、検索エンジン（OpenSearch）、OLTP DB（Aurora）、オブジェクトストレージ（S3 Vectors）という性格の違うサービスを並べ、要件に応じて選ばせる。個々の最適化度は高いが、**どれを選ぶかという設計判断が最初に発生する**。

この差は生成 AI 連携にも表れている。GCP は BigQuery のリモートモデル機構で最初から一体設計。AWS は従来型 ML の `CREATE MODEL` とは別に、Bedrock 専用の `CREATE EXTERNAL MODEL` を用意する二段構え。**このレイヤーの比較が単純な 1 対 1 対応にならない主因がここにある。**

### このレイヤーの未確認事項

- Amazon S3 Vectors の具体的な課金単価。公式ページに明記がなく、S3 の料金ページまでは確認していない。
- AlloyDB AI / Cloud SQL pgvector に、ベクトル検索固有の別建て課金項目があるかどうか。
- Amazon Athena 単体での機械学習統合機能については個別に調査していない。

---

## 7. L5 エージェント／企業内検索

### レイヤーの説明

**基盤モデルに「社内データ」と「道具」を接続するレイヤー。**

L1 の基盤モデルは強力だが、単体では 3 つのことができない。

1. **社内データを知らない。** 学習時点までの一般知識しか持たない。
2. **最新情報を知らない。** 昨日更新された仕様書の内容は答えられない。
3. **副作用のある操作ができない。** 「チケットを起票する」「予約を取る」といった外部システムへの働きかけができない。

これを埋めるのがこのレイヤー。1・2 を解決するのが **RAG**、3 まで含めて解決するのが **エージェント**である。

| | RAG（検索拡張生成） | エージェント |
| --- | --- | --- |
| やること | 質問に関連する社内文書を検索し、その内容を根拠として回答を生成する | 複数ステップの推論を行い、外部ツールを呼び、状態を保持しながらタスクを完遂する |
| 主眼 | 単発の質問応答の精度 | 一連の作業の自動化 |
| 関係 | エージェントが使う道具の 1 つが RAG | RAG を内包しうる上位概念 |

> **このレイヤーは 6 つの中で改称・再編が最も激しい。** 2026 年 7 月時点の正式名称を以下に記す。数か月前の記事の名称はまず通用しない。

### GCP 側サービス

#### Agent Search（旧 Vertex AI Search ほか）

- **一言でいうと**: 自然言語理解・セマンティック検索・生成 AI による要約を組み合わせた、企業向けのマネージド検索エンジン。
- **何を解決するか**: 検索ランキングや RAG の基盤をゼロから作らずに、社内文書や商品カタログに対する高品質な検索を実現する。
- **典型的な使われ方**:
  - 社内 FAQ・マニュアルへの自然言語検索
  - EC サイトの商品検索・レコメンド
  - RAG のバックエンドとしての利用
- **課金単位**: クエリ数（標準クエリと高度なクエリで単価が異なる）＋インデックスしたデータの保存量
- **公式ドキュメント**: https://docs.cloud.google.com/generative-ai-app-builder/docs
- **改称に関する注意**: このサービスは名称変更を繰り返している。公式ドキュメントに次のとおり明記されている。
  > "This product has been renamed since its introduction. Some of the former names include *Vertex AI Search, AI Applications, Agent Builder, Vertex AI Search and Conversation, Enterprise Search,* and *Generative AI App Builder*."

  なお API の基盤は引き続き Discovery Engine API で、コンソール UI には旧称の表記が残っている箇所がある。

#### Agent Builder（ADK / Agent Engine）

- **一言でいうと**: エージェントを「作る・動かす・スケールさせる」ための開発者向け基盤。Agent Development Kit（ADK）でコードを書き、Agent Engine で実行する。
- **何を解決するか**: モデル呼び出し・ツール接続・メモリ・セッション管理・可観測性といった、エージェントを本番運用するための共通インフラを自前で作らずに済ませる。
- **典型的な使われ方**:
  - ADK でエージェントをコードとして実装する
  - Agent Engine にデプロイし、セッションとメモリをマネージドで運用する
  - A2A プロトコルで他フレームワークのエージェントと接続する
- **課金単位**: Agent Engine のランタイムは vCPU 時間とメモリ（GB 時間）の消費量。セッションイベントやメモリの保存は件数
- **公式ドキュメント**: https://docs.cloud.google.com/agent-builder ／ ADK: https://docs.cloud.google.com/gemini-enterprise-agent-platform/build/adk
- **改称に関する注意**: 公式ドキュメントに "Agent Builder has transitioned to become part of Gemini Enterprise Agent Platform" と記載があり、Gemini Enterprise Agent Platform の一部として統合された。

#### Conversational Agents（旧 Dialogflow CX）

- **一言でいうと**: 決定論的な会話フローと生成 AI を組み合わせて構築する対話エージェント基盤。
- **何を解決するか**: コールセンターのように「本人確認や手続きは厳密に制御したいが、雑多な問い合わせには柔軟に答えたい」という、両立の難しい要件に応える。
- **典型的な使われ方**:
  - カスタマーサポートの電話・チャットボット
  - 生成 AI による柔軟な FAQ 対応と、決定論的フローによる厳密な手続き制御の併用
- **課金単位**: セッション数とエディションに応じた従量課金
- **公式ドキュメント**: https://docs.cloud.google.com/dialogflow/cx/docs/concept/console-conversational-agents
- **改称に関する注意**: コンソールの名称が Conversational Agents になったが、裏側の Dialogflow API 自体は変わっていない。

#### Gemini Enterprise

- **一言でいうと**: 社内の複数データソースを横断検索し、AI アシスタントやカスタムエージェントを従業員に届けるエンドユーザー向けの統合ハブ。
- **何を解決するか**: 上記 3 つが開発者向けの部品であるのに対し、これは**業務利用者が直接使う製品**。分散した情報への窓口を一本化し、エージェントの利用を非エンジニアにも開放する。
- **典型的な使われ方**:
  - 社内の各種 SaaS を横断した検索・要約
  - 部門ごとのエージェント（人事、IT、営業支援）のガバナンスつき提供
- **課金単位**: ユーザー単位のライセンス（シート）が中心。裏側の検索・生成の実処理は各基盤側の課金体系に乗る
- **公式ドキュメント**: https://cloud.google.com/gemini-enterprise

### AWS 側サービス

> **AWS はこのレイヤーで第一世代の製品を一斉に畳んでいる。** Bedrock Agents・Amazon Q Business・Amazon Kendra の 3 つが、いずれも **2026 年 7 月 30 日**を境に新規顧客の受付を終了する。以下では後継側を中心に説明する。

#### Amazon Bedrock Knowledge Bases

- **一言でいうと**: 企業データをベクトル化・検索し、基盤モデルに RAG として接続するマネージドサービス。
- **何を解決するか**: ベクトル DB の構築、埋め込み生成、検索精度のチューニングといった作業を肩代わりする。
- **典型的な使われ方**:
  - 製品ドキュメントを根拠にしたカスタマーサポートの自動化
  - SharePoint や Confluence 上の社内情報への質問応答
  - Bedrock AgentCore から呼ぶ RAG ツールとして
- **課金単位**: 基盤モデルのトークン量＋ベクトルストア（OpenSearch Serverless や S3 Vectors など）の利用料の組み合わせ
- **公式ドキュメント**: https://aws.amazon.com/bedrock/knowledge-bases/

#### Amazon Bedrock AgentCore

- **一言でいうと**: 任意のフレームワーク・任意のモデルで作ったエージェントを本番運用するためのプラットフォーム（ランタイム、ゲートウェイ、メモリ、認証、可観測性を提供）。**Bedrock Agents Classic の後継。**
- **何を解決するか**: エージェント開発では、ロジックそのものより「外部システムとの接続」「認証」「スケーリング」「デバッグ」が開発を遅らせる。そこをマネージドサービスとして提供する。
- **典型的な使われ方**:
  - MCP ツールを AgentCore Gateway 経由で公開し、Lambda や REST API に接続する
  - A2A サーバーをホストし、他フレームワーク（LangChain、Strands など）のエージェントと相互接続する
- **課金単位**: ランタイム・メモリ・ゲートウェイといったコンポーネントごとの消費量ベース
- **公式ドキュメント**: https://aws.amazon.com/bedrock/agentcore/ ／ A2A 対応: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-a2a.html

#### Amazon Quick（旧 Amazon Q Business）

- **一言でいうと**: 社内の複数データソースを横断して答える AI アシスタント。Amazon Q Business の後継。
- **何を解決するか**: Q Business 同様の企業内データへの質問応答に加え、ワークフロー自動化（Flows）や BI との統合まで対象を広げている。
- **典型的な使われ方**:
  - 既存の Q Business インデックスを持ち込んで（BYOI）段階的に移行する
  - ネイティブコネクタがない SaaS へ MCP サーバー経由で接続する
- **課金単位**: ユーザー単位のサブスクリプション＋データ容量
- **公式ドキュメント**: https://aws.amazon.com/quick/ ／ 移行ガイド: https://docs.aws.amazon.com/amazonq/latest/qbusiness-ug/qbusiness-availability-change.html

#### Amazon Lex

- **一言でいうと**: インテント（意図）とスロット（項目）をベースに、音声・テキストのボットを構築するサービス。
- **何を解決するか**: コールセンターの自動音声応答のように、あらかじめ定義された対話フローを持つ会話体験を、音声認識と自然言語理解込みで構築する。
- **典型的な使われ方**:
  - コールセンターの自動音声応答（IVR）
  - 定型的な問い合わせ対応チャットボット
  - Amazon Connect との統合による音声ボット
- **課金単位**: リクエスト数（テキスト／音声）
- **公式ドキュメント**: https://aws.amazon.com/lex/

### GCP ↔ AWS 対応表（L5）

| GCP | AWS 相当 | 精度 | ズレの中身 |
| --- | --- | --- | --- |
| Gemini Enterprise | Amazon Quick（旧 Q Business） | ◎ ほぼ同等 | どちらも「社内データ横断＋アシスタント＋簡易自動化」をエンドユーザーに届ける製品という位置づけが一致する |
| Agent Builder（ADK / Agent Engine） | Amazon Bedrock AgentCore | ◎ ほぼ同等 | 開発者向けのエージェント構築・実行基盤という点で近い。ただし **ADK は自社フレームワーク前提の一体型、AgentCore はフレームワーク非依存のモジュール型**という思想差がある |
| Agent Search（旧 Vertex AI Search） | Amazon Bedrock Knowledge Bases | △ 粒度が違う | Agent Search は UI・ランキング・レコメンドまで含むフルスタックの検索製品。Knowledge Bases は RAG 用のデータ接続層で、モデルとの統合は Bedrock 本体が担う。**カバー範囲が違う** |
| Conversational Agents（旧 Dialogflow CX） | Amazon Lex | △ 粒度が違う | Conversational Agents は生成 AI と決定論的フローのハイブリッドで生成 AI ネイティブ度が高い。Lex はインテント／スロット型が基本で、LLM 機能は後付けの位置づけ |

### エージェント連携の標準規格（MCP / A2A）

エージェントが外部ツールや他のエージェントとつながるための標準規格が 2 つあり、**両クラウドとも対応している**。ベンダーロックインを避ける観点で重要な動きなので、発表で触れる価値がある。

| 規格 | 何をつなぐか | GCP | AWS |
| --- | --- | --- | --- |
| **MCP**（Model Context Protocol） | エージェント ↔ 外部ツール・データソース | ADK がクライアント・サーバー双方に対応 | AgentCore Gateway が対応。Amazon Quick も MCP 経由で SaaS に接続 |
| **A2A**（Agent2Agent） | エージェント ↔ 別のエージェント | Agent Engine / ADK がネイティブ対応。Google が主導し Linux Foundation へ寄贈 | AgentCore Runtime が A2A サーバーをホスト可能 |

要するに、**片方のクラウドで作ったエージェントを、もう片方のエージェントから呼ぶことが規格上は可能**になりつつある。

### このレイヤーの設計思想の違い

GCP は Gemini Enterprise Agent Platform という単一ブランドの下に、開発者向け（Agent Builder）とエンドユーザー向け（Gemini Enterprise）を分けつつ密結合させる方向へ進んでいる。頻繁な改称は、この統合を段階的に進めている過程の反映と読める。

AWS は Knowledge Bases / AgentCore Gateway / AgentCore Runtime / AgentCore Memory のように機能を独立したコンポーネントとして提供し、**「任意のフレームワーク・任意のモデル」を掲げて自社フレームワークへのロックインを避ける**組み合わせ型を志向する。

そして畳み方が対照的である。**AWS は 2026 年 7 月 30 日という同一の日付で、Q Business・Bedrock Agents・Kendra という第一世代 3 製品の新規受付を一斉に終了させ、明確な世代交代を宣言した。** GCP の緩やかなブランド統合とは、意思決定の断ち切り方が違う。

### 2026 年時点の改称・統廃合（このレイヤーは特に重要）

| 旧名称 | 現在 | 状況 |
| --- | --- | --- |
| Vertex AI Search / AI Applications / Agent Builder / Enterprise Search / Generative AI App Builder | **Agent Search** | 公式ドキュメントに旧称一覧が明記されている。コンソール UI には旧称が残る |
| Vertex AI（Agent Builder） | **Gemini Enterprise Agent Platform** の一部 | 2026 年 4 月統合 |
| Dialogflow CX（コンソール） | **Conversational Agents** | API 自体は変更なし |
| Amazon Q Business | **Amazon Quick** | 2026-07-31 から新規受付終了（7/30 までに登録が必要）。既存顧客は継続サポートされるが、新機能追加はなし |
| Amazon Bedrock Agents | **Amazon Bedrock Agents Classic** | 2026-07-30 から新規受付終了。後継は AgentCore。既存顧客は継続利用可 |
| Amazon Kendra | （後継の明示なし。Bedrock Knowledge Bases を案内） | 2026-07-30 から新規受付終了 |

公式ドキュメントの原文（Bedrock Agents）:
> "Amazon Bedrock Agents (launched November 2023) is now 'Amazon Bedrock Agents Classic' and will no longer be open to new customers starting on July 30, 2026. For capabilities similar to Bedrock Agents Classic, explore Amazon Bedrock AgentCore. ... Existing customers can continue to use the service as normal."

### このレイヤーの未確認事項

- **Agentspace から Gemini Enterprise への改称**は、複数の情報源で言及されているものの、公式ページ本文での裏取りができなかった（ページが JavaScript 描画中心のため取得不可）。現行名称が Gemini Enterprise であることは確認済み。
- A2A プロトコルの 2026 年 7 月時点での正式バージョン番号。
- Bedrock Knowledge Bases の標準利用時における、トークン量とベクトルストア料金の正確な内訳。

---

## 8. L6 開発者・運用者向け AI アシスタント

### レイヤーの説明

**このレイヤーだけ性格が違う。** L1〜L5 が「アプリに組み込む部品」なのに対し、ここは **クラウド事業者が自社の開発者・運用者に向けて提供する、開発体験・運用体験そのものを支援するツール**である。何かを作るためのサービスではなく、作る作業自体を速くするためのもの。

大きく 2 系統に分かれる。

1. **コーディング支援** —— IDE 拡張やターミナルのエージェントによるコード生成・補完
2. **運用支援** —— コンソールや監視サービスに統合された、障害調査・コスト最適化の支援

第三者製品（GitHub Copilot、Cursor など）と違い、**自社クラウドのリソース（IAM、Terraform、CloudWatch など）への深い統合**が売りになる。

> **このレイヤーは製品の登場・改称が最も速い。** 特に 2026 年に入って両社とも個人向けの入口を再編している最中で、以下の内容も数か月で変わる可能性が高い。

### GCP 側サービス

#### Gemini Code Assist

- **一言でいうと**: IDE に統合された AI コーディング支援サービス。
- **何を解決するか**: コード補完・生成、チャットでの相談、テスト生成、デバッグを通じて開発を支援する。Standard は基本的な用途、Enterprise は自社コードベースに合わせたカスタマイズ向け。
- **典型的な使われ方**:
  - VS Code / JetBrains / Android Studio に拡張を入れてチャット・コード生成
  - Enterprise では社内コードベースに沿った提案を受ける
- **課金単位**: ユーザー単位のサブスクリプション（Standard / Enterprise）
- **公式ドキュメント**: https://docs.cloud.google.com/gemini/docs/codeassist/overview
- **重要な変更**: **個人向けの無料枠は終了している。** 公式ドキュメントに次のとおり明記されている。
  > "Starting June 18, 2026, Gemini Code Assist IDE Extensions and Gemini CLI stopped serving requests for the Gemini Code Assist for individuals, Google AI Pro, and Google AI Ultra tiers."

  個人利用者は **Antigravity**（https://antigravity.google/ ）への移行が案内されている。法人向けの Standard / Enterprise はこの影響を受けない。

#### Gemini CLI

- **一言でいうと**: ターミナルから Gemini を呼び出せるオープンソースのエージェント型 CLI。
- **何を解決するか**: 推論と実行を繰り返すループで、バグ修正・機能実装・テスト追加といった作業をターミナル上で完結させる。
- **典型的な使われ方**:
  - Gemini Code Assist の VS Code エージェントモードの実行エンジンとして
  - MCP サーバーや検索と連携した調査・実装タスク
- **課金単位**: Gemini Code Assist の各エディションのライセンスに割り当てが含まれる
- **公式ドキュメント**: https://docs.cloud.google.com/gemini/docs/codeassist/gemini-cli
- **注意**: 上記のとおり、個人向け無料枠経由の利用は 2026-06-18 に終了し、Antigravity CLI へ移行している。

#### Gemini Cloud Assist

- **一言でいうと**: 設計・構築・障害調査・コスト最適化を横断する、クラウド運用向けの AI 支援機能。
- **何を解決するか**: DevOps / SRE / クラウド管理者の日常業務を簡素化し、障害の根本原因分析（RCA）を速める。
- **典型的な使われ方**:
  - アラート発生時にログとメトリクスを横断分析し、原因の仮説を提示する
  - コスト異常の検知と最適化提案
  - 自然言語からの IaC（Terraform / kubectl）生成
- **課金単位**: 公式ドキュメントに明記なし（プレビュー段階であることのみ確認）
- **公式ドキュメント**: https://docs.cloud.google.com/cloud-assist/overview

### AWS 側サービス

#### Amazon Q Developer

- **一言でいうと**: AWS アプリケーションの理解・構築・拡張・運用を助ける生成 AI アシスタント。Amazon Bedrock 上に構築されている。
- **何を解決するか**: コードの説明・補完・生成、セキュリティスキャン、言語バージョンのアップグレードといった作業に加え、AWS のアーキテクチャや自分のリソースについての質問に答える。
- **典型的な使われ方**:
  - VS Code / JetBrains / Visual Studio / Eclipse の拡張でチャット・コード補完
  - AWS マネジメントコンソールやドキュメントサイト上での質問
  - Slack / Microsoft Teams からの利用
- **課金単位**: 無料枠と Pro サブスクリプション（ユーザー単位の月額）
- **公式ドキュメント**: https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/what-is.html

#### Kiro

- **一言でいうと**: AWS が提供する、仕様駆動（spec-driven）のエージェント型 AI IDE。
- **何を解決するか**: プロンプトだけに頼る開発では、複雑なタスクで文脈の取り違えや手戻りが起きる。そこで要件定義と設計を先に固めてから実装に進むフローを標準にしている。
- **典型的な使われ方**:
  - プロンプトから要件・設計ドキュメントを生成し、それをもとに実装させる
  - Kiro CLI によるターミナルからの自然言語操作
- **課金単位**: クレジット制の前払い。使うモデルによって消費量が変動する
- **公式ドキュメント**: https://kiro.dev/ ／ CLI: https://kiro.dev/docs/cli
- **重要な変更**: **Amazon Q Developer の CLI は Kiro CLI に統合された。** AWS 公式ドキュメントに次のとおり明記されている。
  > "The Q CLI has become the Kiro CLI."

  （出典: https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/command-line.html ）

#### CloudWatch investigations

- **一言でいうと**: CloudWatch に組み込まれた、生成 AI によるインシデント対応の支援機能。
- **何を解決するか**: アラーム発生時に、メトリクス・ログ・デプロイイベント・トレース・設定変更履歴を横断して分析し、根本原因の仮説を提示する。手作業でログを漁る時間を削る。
- **典型的な使われ方**:
  - アラームや Logs Insights のクエリからそのまま調査を開始する
  - 複数アカウントをまたいだ調査、自動修復の提案
  - 調査結果のチーム共有・レポート生成
- **課金単位**: アカウントあたり月次の無料枠があり、それを超えると従量課金
- **公式ドキュメント**: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Investigations.html

### GCP ↔ AWS 対応表（L6）

| GCP | AWS 相当 | 精度 | ズレの中身 |
| --- | --- | --- | --- |
| Gemini Code Assist（Standard / Enterprise） | Amazon Q Developer ／ Kiro | △ 粒度が違う | GCP は法人向け（Code Assist）を維持しつつ個人向けを Antigravity へ分離した。AWS は Q Developer と Kiro が併存しており、**両社とも再編中で対応が非対称**。詳細は下の注意を参照 |
| Gemini CLI | Kiro CLI（旧 Amazon Q Developer CLI） | ◎ ほぼ同等 | どちらもターミナル常駐のエージェント型 CLI。AWS 側はブランドごと Kiro CLI に移行済みで、これは公式に明記されている |
| Gemini Cloud Assist | CloudWatch investigations | △ 粒度が違う | Gemini Cloud Assist は設計・構築・障害調査・コスト最適化まで横断する（プレビュー）。CloudWatch investigations は障害の根本原因分析に特化しており、対象範囲が狭い |

### このレイヤーの設計思想の違い

GCP は **コーディング支援と運用支援をブランドで明確に分けている**（Gemini Code Assist / Gemini CLI 対 Gemini Cloud Assist）。さらにコーディング支援の中でも、法人向け（Code Assist）と個人向け（Antigravity）を別ブランドに切り分ける方向へ進んでいる。

AWS は元々 Amazon Q Developer という単一ブランドの下に IDE 拡張・CLI・コンソールチャットを束ねていたが、**CLI については Kiro CLI へ移行済み**であることが公式に確認できる。IDE 統合の方針では、GCP が既存 IDE（VS Code / JetBrains）へのプラグイン提供を維持するのに対し、AWS は自社の AI IDE である Kiro を打ち出しており、「既存 IDE への後付け」対「専用 IDE への統合」という対照が見える。

運用支援を、コーディング支援とは別サービスとして扱う点は両社共通である。

### このレイヤーの未確認事項

**この項目は特に注意して読むこと。調査段階で誤った情報が混入し、公式ドキュメントで否定された経緯がある。**

- **Amazon Q Developer 本体の終了について、公式ユーザーガイドには告知が存在しない。** 調査の過程で「2027 年 4 月 30 日にサポート終了」という情報が出てきたが、公式ドキュメント（https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/what-is.html ）を確認したところ、終了に関する記述はなく、IDE 拡張の導入を現役の手順として案内している。**確認できたのは CLI の Kiro CLI への移行のみ。** 本文でもその範囲に限定して記載した。
- Gemini Code Assist Standard / Enterprise の正確な料金額（公式サイトが JavaScript 描画中心で本文を取得できなかった）。
- Gemini Cloud Assist が現在もプレビュー段階か、一般提供に移行したか。
- Kiro のクレジット消費レートの詳細と無料枠の有無。

---

## 9. 両クラウドの設計思想の違い

ここまでの 6 レイヤーを通して見えるものをまとめる。**このセクションは事実の列挙ではなく、対応表から読み取った解釈である。**

### 9.1 束ねる GCP、分ける AWS

最も一貫している差がこれ。

| レイヤー | GCP（束ねる） | AWS（分ける） |
| --- | --- | --- |
| L1 | Model Garden に自社・他社モデルを集約。ただし入口は AI Studio と Agent Platform に分離 | Bedrock 一つに全部フラットに並べる |
| L2 | Gemini Enterprise Agent Platform に ML 機能を統合 | SageMaker AI の中に機能を持つが、上位に統合基盤を別途新設 |
| L4 | **BigQuery 一つで従来型 ML・ベクトル検索・生成 AI 呼び出しが完結** | **Redshift ML・OpenSearch・Aurora pgvector・S3 Vectors を組み合わせる** |
| L5 | Gemini Enterprise Agent Platform に開発者向けもエンドユーザー向けも集約 | Knowledge Bases / AgentCore の各コンポーネントを組み合わせる |

**それぞれの利点と欠点**は次のとおり。

| | 束ねる（GCP） | 分ける（AWS） |
| --- | --- | --- |
| 学習コスト | 低い。入口が一つ | 高い。どれを選ぶかの判断が先に来る |
| 初期の立ち上がり | 速い | 遅い |
| 個別最適 | しにくい | しやすい。用途特化のサービスを選べる |
| 名称の安定性 | **低い。ブランド統合のたびに改称される** | 比較的高い。ただし世代交代時は打ち切られる |

L4 がこの差を最も鮮明に示す。**BigQuery で ML をやる場合、覚えるのは SQL だけでよい。** AWS で同じことをするには、まず「DWH の中でやるか、検索エンジンを立てるか、DB に同居させるか、S3 に置くか」を決める必要がある。

### 9.2 「✕ 相当なし」の行が示すもの

対応表で ✕ が付いた 3 箇所は、いずれも片方のクラウドにしかない発想である。

| ✕ の項目 | どちらにある | 何を示すか |
| --- | --- | --- |
| BigQuery のベクトル検索 | GCP のみ | **データウェアハウスそのものにベクトル検索を埋め込む**という発想。AWS の Redshift にはネイティブ機能がない |
| Amazon S3 Vectors | AWS のみ | **オブジェクトストレージにベクトルインデックスを持たせる**という新カテゴリ。低コストの長期保存に振った設計 |
| Google AI Studio | GCP のみ | **API キーだけで始められる軽量な入口**。AWS は全サービスが AWS アカウント前提で統一されている |

前 2 つは、それぞれのクラウドの中核資産（GCP は BigQuery、AWS は S3）に AI 機能を寄せた結果である。**両社とも「自分たちの一番強いデータ基盤に AI を載せる」という戦略は同じで、その基盤が違うから出てくる答えが違う。**

### 9.3 名称の変わりやすさは無視できないコスト

本資料の調査で確認できた、直近 2 年ほどの主な改称・世代交代は以下のとおり。

| クラウド | 変更 | 時期 |
| --- | --- | --- |
| GCP | Vertex AI → Gemini Enterprise Agent Platform | 2026-04 |
| GCP | Vertex AI Search ほか → Agent Search | 複数回 |
| GCP | Dialogflow CX → Conversational Agents（コンソール） | — |
| GCP | Gemini Code Assist 個人向け → Antigravity | 2026-06-18 |
| AWS | Amazon SageMaker → Amazon SageMaker AI | 2024-12 |
| AWS | Bedrock Agents → Bedrock Agents Classic（新規受付終了） | 2026-07-30 |
| AWS | Amazon Q Business → Amazon Quick（新規受付終了） | 2026-07-31 |
| AWS | Amazon Kendra 新規受付終了 | 2026-07-30 |
| AWS | Amazon Q Developer CLI → Kiro CLI | — |
| AWS | Nova Canvas / Nova Reel の EOL | 2026-09-30 |

ここから言えることが 3 つある。

1. **社内ドキュメントやブログ記事は急速に陳腐化する。** 半年前の資料の名称は、そのままでは通じない可能性が高い。
2. **改称の仕方に性格が出ている。** GCP は改称してもサービスは存続し、API エンドポイントも維持される（機能を畳むのではなく、ブランドに吸収する）。AWS は名前を変えるより**製品ごと新規受付を止めて後継へ誘導する**。既存顧客は守るが、新規は後継へ寄せる、という明確な線引きをする。
3. **今から学ぶなら後継側を見るべき。** AWS でエージェントを学ぶなら Bedrock Agents ではなく AgentCore、企業内検索なら Kendra ではなく Bedrock Knowledge Bases が入口になる。

### 9.4 実務的な選定の目安

対応表から導ける、素朴な指針。

| 状況 | 寄りやすいクラウド | 理由 |
| --- | --- | --- |
| **日本語の帳票・画像 OCR が要件にある** | **GCP** | Textract・Rekognition DetectText が日本語非対応。この 1 点で決まることがある |
| すでに BigQuery にデータが集まっている | GCP | L4 でデータを動かさずに ML と生成 AI が完結する |
| すでに S3 中心のデータレイクがある | AWS | S3 Vectors や Bedrock Knowledge Bases との接続が素直 |
| 複数ベンダーのモデルを比較しながら使いたい | どちらでも可 | Model Garden と Bedrock がほぼ同等 |
| エージェントのフレームワークを自分で選びたい | AWS | AgentCore がフレームワーク非依存を掲げている |
| 少人数で早く立ち上げたい | GCP | 束ねる設計のぶん、選定の判断が少ない |

---

## 10. 用語コラム

本文に出てきた AI 特有の用語を、最小限の定義でまとめる。

| 用語 | 定義 |
| --- | --- |
| **学習（トレーニング）** | データからモデルのパラメータを決める処理。計算資源を大量に消費し、時間もかかる。**一度やれば済む**（作り直すまで） |
| **推論（インファレンス）** | 学習済みモデルに入力を与えて結果を得る処理。**リクエストのたびに発生する**。本番運用のコストの大半はこちら |
| **基盤モデル（Foundation Model）** | 大量の汎用データで事前学習された巨大なモデル。特定のタスク向けではなく、幅広い用途に応用できる。Gemini、Claude、Nova などがこれ |
| **ファインチューニング** | 基盤モデルに追加の学習をさせ、特定の用途やデータに合わせて調整すること。RAG と違い、モデルそのものを書き換える |
| **プロンプト** | モデルへの指示文。同じモデルでも指示の書き方で結果が大きく変わる |
| **トークン** | モデルがテキストを扱う単位。単語より細かく、文字より粗い。日本語は英語よりトークン数が多くなりやすく、**課金単位がトークンである以上、これはコストに直結する** |
| **マルチモーダル** | テキストだけでなく、画像・音声・動画も同時に扱えること。Gemini や Claude が該当する |
| **埋め込み（Embedding）** | テキストや画像を、意味を保った数値のベクトルに変換したもの。意味が近いもの同士は、ベクトルとしても近い位置になる |
| **ベクトル検索** | 埋め込みベクトル同士の距離を測って、意味的に近いものを探す検索。キーワードが一致しなくても「意味が近い」文書を見つけられる |
| **近似最近傍検索（ANN）** | ベクトル検索を高速化する手法。厳密に最も近いものを探すのではなく、十分近いものを高速に返す。大規模データではこれが実用上必須になる |
| **RAG（検索拡張生成）** | 質問に関連する文書をまず検索し、その内容を根拠としてモデルに回答させる仕組み。モデルを再学習せずに社内データを扱えるのが利点 |
| **グラウンディング** | モデルの回答を、実在する情報源に紐づけること。RAG はグラウンディングの手段の一つ。これがないとモデルは平然と誤情報を生成する |
| **ハルシネーション** | モデルが事実でない内容を、もっともらしく生成してしまう現象 |
| **エージェント** | 複数ステップの推論を行い、外部ツールを呼び、状態を保持しながらタスクを完遂する仕組み。単発の質問応答（RAG）より上位の概念 |
| **ツール／関数呼び出し** | モデルが外部の API や関数を呼べるようにする仕組み。エージェントが実際に「行動」できるのはこれによる |
| **MCP（Model Context Protocol）** | エージェントと外部ツール・データソースをつなぐ標準規格。両クラウドが対応している |
| **A2A（Agent2Agent）** | エージェント同士をつなぐ標準規格。Google が主導し、Linux Foundation へ寄贈された |
| **MLOps** | 機械学習モデルの開発から本番運用までを継続的に回すための実践。学習・評価・デプロイ・監視・再学習のサイクル |
| **特徴量（Feature）** | モデルへの入力として使う、データから抽出した数値。「直近 30 日の購入回数」など |
| **AutoML** | データを与えるだけで、モデルの選定・チューニングまで自動で行う仕組み |
| **OCR** | 画像内の文字を読み取ってテキスト化する技術。近年は文書の構造まで理解する方向に進化している |

---

## 11. 参考リンク一覧

**すべて公式ドキュメント。調査日（2026-07-29）時点で HTTP 200 を確認済み。**

### L1 基盤モデル API

| サービス | URL |
| --- | --- |
| Gemini API | https://ai.google.dev/gemini-api/docs |
| Gemini API 料金 | https://ai.google.dev/gemini-api/docs/pricing |
| Model Garden | https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-garden/explore-models |
| Imagen | https://docs.cloud.google.com/vertex-ai/generative-ai/docs/image/overview |
| Veo | https://docs.cloud.google.com/vertex-ai/generative-ai/docs/video/overview |
| Amazon Bedrock | https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html |
| Amazon Bedrock 製品ページ | https://aws.amazon.com/bedrock/ |
| Amazon Bedrock 料金 | https://aws.amazon.com/bedrock/pricing/ |
| Amazon Nova | https://aws.amazon.com/nova/ |
| Nova Canvas モデルカード（EOL 記載） | https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-nova-canvas.html |

### L2 ML プラットフォーム

| サービス | URL |
| --- | --- |
| Vertex AI Training | https://docs.cloud.google.com/gemini-enterprise-agent-platform/machine-learning/training-overview |
| Vertex AI Prediction | https://docs.cloud.google.com/gemini-enterprise-agent-platform/machine-learning/start/predictions-guide |
| Vertex AI Pipelines | https://docs.cloud.google.com/gemini-enterprise-agent-platform/machine-learning/pipelines/introduction |
| Vertex AI Model Registry | https://docs.cloud.google.com/gemini-enterprise-agent-platform/machine-learning/model-registry/introduction |
| Vertex AI Feature Store | https://docs.cloud.google.com/gemini-enterprise-agent-platform/machine-learning/featurestore/latest/overview |
| AutoML | https://docs.cloud.google.com/gemini-enterprise-agent-platform/machine-learning/training/automl-training-overview |
| Gemini Enterprise Agent Platform（トップ） | https://docs.cloud.google.com/gemini-enterprise-agent-platform |
| 改称の発表（公式ブログ） | https://cloud.google.com/blog/products/ai-machine-learning/introducing-gemini-enterprise-agent-platform |
| SageMaker AI 概要 | https://docs.aws.amazon.com/sagemaker/latest/dg/whatis.html |
| SageMaker AI Training | https://docs.aws.amazon.com/sagemaker/latest/dg/how-it-works-training.html |
| SageMaker AI 推論 | https://docs.aws.amazon.com/sagemaker/latest/dg/deploy-model.html |
| SageMaker AI Pipelines | https://docs.aws.amazon.com/sagemaker/latest/dg/pipelines.html |
| SageMaker AI Model Registry | https://docs.aws.amazon.com/sagemaker/latest/dg/model-registry.html |
| SageMaker AI Feature Store | https://docs.aws.amazon.com/sagemaker/latest/dg/feature-store.html |
| SageMaker AI Studio | https://docs.aws.amazon.com/sagemaker/latest/dg/studio-updated.html |
| SageMaker AI Canvas | https://docs.aws.amazon.com/sagemaker/latest/dg/canvas.html |

### L3 タスク特化 API

| サービス | URL |
| --- | --- |
| Document AI | https://docs.cloud.google.com/document-ai/docs/overview |
| Document AI 対応言語 | https://docs.cloud.google.com/document-ai/docs/languages |
| Cloud Speech-to-Text | https://docs.cloud.google.com/speech-to-text/docs |
| Speech-to-Text 対応言語 | https://docs.cloud.google.com/speech-to-text/docs/languages |
| Cloud Vision API | https://docs.cloud.google.com/vision/docs |
| Vision API 対応言語 | https://docs.cloud.google.com/vision/docs/languages |
| Cloud Translation API | https://docs.cloud.google.com/translate/docs |
| Cloud Text-to-Speech | https://docs.cloud.google.com/text-to-speech/docs |
| Cloud Natural Language API | https://docs.cloud.google.com/natural-language/docs |
| Video Intelligence API | https://docs.cloud.google.com/video-intelligence/docs |
| Amazon Textract | https://docs.aws.amazon.com/textract/latest/dg/what-is.html |
| **Textract 対応言語（日本語非対応の明記）** | https://docs.aws.amazon.com/textract/latest/dg/textract-best-practices.html |
| Amazon Transcribe | https://docs.aws.amazon.com/transcribe/latest/dg/what-is.html |
| Transcribe 対応言語 | https://docs.aws.amazon.com/transcribe/latest/dg/supported-languages.html |
| Amazon Rekognition | https://docs.aws.amazon.com/rekognition/latest/dg/what-is.html |
| Amazon Translate | https://docs.aws.amazon.com/translate/latest/dg/what-is.html |
| Amazon Comprehend | https://docs.aws.amazon.com/comprehend/latest/dg/what-is.html |
| Amazon Polly | https://docs.aws.amazon.com/polly/latest/dg/what-is.html |

### L4 データ基盤に統合された AI

| サービス | URL |
| --- | --- |
| BigQuery ML | https://docs.cloud.google.com/bigquery/docs/bqml-introduction |
| BigQuery の生成 AI 連携 | https://docs.cloud.google.com/bigquery/docs/generative-ai-overview |
| BigQuery ベクトル検索 | https://docs.cloud.google.com/bigquery/docs/vector-search-intro |
| BigQuery ベクトルインデックス | https://docs.cloud.google.com/bigquery/docs/vector-index |
| Vertex AI Vector Search | https://docs.cloud.google.com/vertex-ai/docs/vector-search/overview |
| AlloyDB AI ベクトル検索 | https://docs.cloud.google.com/alloydb/docs/ai/vector-search-overview |
| Amazon Redshift ML | https://docs.aws.amazon.com/redshift/latest/dg/machine_learning_overview.html |
| Redshift ML の Bedrock 連携 | https://docs.aws.amazon.com/redshift/latest/dg/machine-learning-br.html |
| Redshift ML のコスト | https://docs.aws.amazon.com/redshift/latest/dg/cost.html |
| OpenSearch k-NN | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/knn.html |
| OpenSearch Serverless ベクトル検索 | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless-vector-search.html |
| Aurora PostgreSQL pgvector | https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraPostgreSQL.VectorDB.html |
| Amazon S3 Vectors | https://aws.amazon.com/s3/features/vectors/ |

### L5 エージェント／企業内検索

| サービス | URL |
| --- | --- |
| Agent Search（旧称一覧の記載あり） | https://docs.cloud.google.com/generative-ai-app-builder/docs |
| Agent Builder | https://docs.cloud.google.com/agent-builder |
| Agent Development Kit（ADK） | https://docs.cloud.google.com/gemini-enterprise-agent-platform/build/adk |
| Agent Engine の A2A 対応 | https://docs.cloud.google.com/agent-builder/agent-engine/use/a2a |
| Conversational Agents | https://docs.cloud.google.com/dialogflow/cx/docs/concept/console-conversational-agents |
| Gemini Enterprise | https://cloud.google.com/gemini-enterprise |
| Bedrock Knowledge Bases | https://aws.amazon.com/bedrock/knowledge-bases/ |
| Bedrock AgentCore | https://aws.amazon.com/bedrock/agentcore/ |
| AgentCore の A2A 対応 | https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-a2a.html |
| **Bedrock Agents Classic 化の告知** | https://docs.aws.amazon.com/bedrock/latest/userguide/agents.html |
| Bedrock Agents Classic メンテナンスモード | https://docs.aws.amazon.com/bedrock/latest/userguide/agents-classic-maintenance-mode.html |
| Amazon Quick | https://aws.amazon.com/quick/ |
| **Q Business → Quick 移行の告知** | https://docs.aws.amazon.com/amazonq/latest/qbusiness-ug/qbusiness-availability-change.html |
| **Kendra 新規受付終了の告知** | https://docs.aws.amazon.com/kendra/latest/dg/kendra-availability-change.html |
| Amazon Lex | https://aws.amazon.com/lex/ |

### L6 開発者・運用者向け AI

| サービス | URL |
| --- | --- |
| Gemini Code Assist | https://docs.cloud.google.com/gemini/docs/codeassist/overview |
| Gemini CLI | https://docs.cloud.google.com/gemini/docs/codeassist/gemini-cli |
| Antigravity（個人向けの移行先） | https://antigravity.google/ |
| Gemini Cloud Assist | https://docs.cloud.google.com/cloud-assist/overview |
| Amazon Q Developer | https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/what-is.html |
| **Q CLI → Kiro CLI の告知** | https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/command-line.html |
| Kiro | https://kiro.dev/ |
| Kiro CLI | https://kiro.dev/docs/cli |
| CloudWatch investigations | https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Investigations.html |
</content>
</invoke>
