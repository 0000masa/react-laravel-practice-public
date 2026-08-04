# フロントエンド／ブラウザの OpenTelemetry（Browser SDK）まとめ

対象記事: [フロントエンドに広がる OpenTelemetry：Browser SDK の現在地](https://zenn.dev/cybozu_frontend/articles/opentelemetry-browser-frontend)（cybozu frontend）

このノートは上記記事とそのコメント欄を要約し、初見の専門用語を後半の「用語コラム」で補足したもの。
このリポジトリのバックエンド（ECS + ADOT Collector サイドカー）との対比も含める。

---

## 0. まず結論: ブラウザの Collector はどこで動くか

このリポジトリのバックエンドは **OpenTelemetry Collector をサイドカー**として動かしている。

| | このリポジトリの backend (ECS Fargate) | ブラウザ (フロントエンド) |
| --- | --- | --- |
| Collector の置き場所 | 同一タスク内のサイドカーコンテナ（`adot-collector`） | **ブラウザには置かない。サーバー側に立てた Collector へ送る** |
| アプリからの送信先 | `http://localhost:4318`（同一タスク内なので localhost で届く） | 公開エンドポイント（例 `https://otel.example.com/v1/traces`） |
| プロトコル | OTLP/HTTP (`http/protobuf`) | OTLP/HTTP |
| オリジンをまたぐか | またがない（同一タスク内） | **またぐ → CORS 設定が必要** |

このリポジトリの実装箇所:

- サイドカー定義: `ecspresso/stg/web/ecs-task-def.jsonnet:52`（`image: public.ecr.aws/aws-observability/aws-otel-collector`、ポート `4317`/`4318`）
- アプリ側の送信先: `ecspresso/_common.libsonnet:33`（`OTEL_EXPORTER_OTLP_ENDPOINT = http://localhost:4318`）

### なぜブラウザには置けないのか

1. **Collector 本体は Go 製のサーバープロセス。** ブラウザの JavaScript 実行環境では動かせない。
2. **`localhost` が使えない。** ブラウザにとっての `localhost` は「利用者の PC」であり、こちらのサーバーではない。したがって Collector は名前解決できる**公開エンドポイント**でなければ届かない。
3. **別オリジンへの送信になる。** ブラウザから別ホストの Collector へ POST するため CORS が発生する。記事が「CORS 設定」「本番では許可オリジンを設計せよ」と述べているのはこの理由。

つまりブラウザの構図は「**公開された Collector に、CORS を越えて、ネットワーク経由で OTLP/HTTP を送る**」。サイドカーで localhost 完結できた backend とはここが決定的に違う。

### 送信先の公開エンドポイントは何を指すか（誤解しやすい点）

上表の例 `https://otel.example.com/v1/traces` は **OpenTelemetry 公式が提供するクラウド上の Collector ではない**。OpenTelemetry はベンダー中立の「仕様とツール」を提供するプロジェクトであり、テレメトリを預かる SaaS は運営していない。したがって送信先は自分で用意する必要があり、選択肢は次の 2 つ。

| 選択肢 | 中身 | このリポジトリで例えると |
| --- | --- | --- |
| ① 自前ホストの Collector | 自分たちで Collector を立て、前段に公開エンドポイントを置く | **ALB + ECS Fargate で Collector を動かす**（例 `https://otel.example.com/...` はこれ） |
| ② ベンダーの OTLP 受信エンドポイント | Grafana Cloud / Datadog / Honeycomb / New Relic 等が提供する OTLP 直受け URL に送る | そのベンダーの URL（例 `https://otlp-gateway-....grafana.net/otlp`）。自前 Collector を省ける構成もある |

`https://otel.example.com/v1/traces` は **①（自前ホスト）** のイメージ。「自分たちが ALB + ECS などで用意したサーバーのエンドポイントに送る」で正しい。

backend との対比:

- backend（ECS サイドカー）: アプリ → `localhost:4318` の Collector → 保存先（X-Ray 等）へ Collector が転送。
- browser（自前ホスト①）: ブラウザ → 公開エンドポイント（ALB）→ ECS 上の Collector → 保存先へ転送。

「Collector が最終保存先ではなく中継役」という点は backend も browser も同じ。違うのは Collector への到達経路だけ（localhost か、インターネット越しの ALB か）。

②で直送もできるのに①の自前 Collector を挟む利点: 送信先ベンダーを 1 か所で切替可能、PII のマスキングやサンプリングを集中管理できる、ブラウザに送信先の認証情報を持たせず Collector 側で付与できる。

---

## 1. 記事の主題と背景

- テーマ: **ブラウザ向け OpenTelemetry SDK（Browser SDK）の開発が進み、フロントエンド監視でも使えるようになりつつある**という現在地の報告。
- 背景: OpenTelemetry はサーバーサイドでは広く採用済み。一方フロントエンド監視は **Sentry / Datadog** などの SaaS 独自 SDK（RUM SDK）が主流だった。
- OpenTelemetry の目的: 計装の API とデータ形式を標準化し、特定ベンダー SDK への依存を減らすこと。
- 成熟度: **2026 年 5 月に CNCF の Graduated Project に認定**。
- 残課題: SaaS の RUM が持つ機能をすべて置き換えるには、**ソースマップによるエラー復元**と **Session Replay** の扱いが実用上のネックとして残る。

---

## 2. ブラウザ SDK の 2 つの設計: スパンベース と イベントベース

OpenTelemetry のブラウザ SDK には、性質の違う 2 つの計装設計が共存している。

| | スパンベース (`Span`) | イベントベース (`LogRecord`) |
| --- | --- | --- |
| 時間の持ち方 | 開始と終了がある（所要時間 = duration を持つ） | 一瞬の点（発生時刻のみ） |
| 表すもの | 「処理」= 始まって終わる一連の動作 | 「出来事」= その瞬間に起きたこと |
| 親子関係 | 持てる（Span の中に子 Span がネストする） | 基本持たない |
| ブラウザでの例 | `fetch` / `XMLHttpRequest`、ページ読み込み | User Action（操作）、Web Vitals のスコア、Console 出力、エラー |
| 代表パッケージ | `instrumentation-fetch`, `instrumentation-document-load` | `@opentelemetry/browser-instrumentation` |

成熟度の注意:

- `@opentelemetry/sdk-trace-web`（スパンベースの土台）は**安定版**。
- それ以外（イベントベース含む）は **experimental** 段階。

---

## 3. 計装対象（何を自動で観測できるか）

| 分類 | 取れるもの | 送られ方 |
| --- | --- | --- |
| Navigation / Navigation Timing / Resource Timing | ページ遷移・読み込み・リソース取得の時間 | Span |
| Fetch / XMLHttpRequest | API 通信の開始〜終了・ステータス | Span |
| User Action | クリック等のユーザー操作 | LogRecord |
| Web Vitals | Core Web Vitals（LCP / INP / CLS 等）のスコア | LogRecord |
| Console | `console.*` の出力 | LogRecord |
| Errors | 未処理エラー・Promise reject | LogRecord |

---

## 4. 送信構成（ブラウザ → Collector）

- **プロトコル**: OTLP/HTTP でエクスポート（`OTLPTraceExporter`, `OTLPLogExporter`）。
- **エンドポイント**:
  - Traces: `/v1/traces`
  - Logs: `/v1/logs`
- **検証環境の Collector**: Docker Compose で `grafana/otel-lgtm:0.29.1` を使用。ポート `4318` で OTLP/HTTP receiver を公開し、内部で Grafana / Loki / Tempo が統合されている（= LGTM スタック）。
- **CORS**: LGTM イメージの標準設定では HTTP スキームの全オリジンからの OTLP/HTTP を許可している。**本番では公開方法と許可オリジンを別途設計する必要がある**（記事の明記事項）。
- **サービス名**: 検証では `otel-browser-with-tracing` を使用。

### セッションでのトレース／ログ横断

- Span の attributes に `session.id` を設定する。
- 同じ `session.id` で Loki のログ検索をすれば、そのセッションで収集した Core Web Vitals スコアなども横断的に確認できる。
- Span（スパンベース）と LogRecord（イベントベース）を **同一セッションとして紐付ける**ための鍵が `session.id`。

---

## 5. 実装上の注意点・ハマりどころ

| 論点 | 内容 |
| --- | --- |
| Collector URL の自己計装ループ | OTLP 送信自体が Fetch/XHR の Span として計装されないよう、Collector の URL を各 Instrumentation の `ignoreUrls` に指定する |
| 非同期コンテキスト伝播 | ブラウザには `await` をまたいで Context を保持する標準機構がない（後述の用語コラム参照）。Zone.js / unctx / AsyncContext proposal が検討対象 |
| パフォーマンス配慮 | Resource Timing の実装は `requestIdleCallback` でアイドル時間に処理し、バッチサイズ等を調整可能にしている |

### 残課題（SaaS RUM の完全置き換えに向けて）

- **ソースマップによるエラー復元**: minify 済みコードのスタックトレースを元コードに復元する処理。
- **Session Replay**: ユーザー操作の再生機能。

---

## 6. コメント欄の論点と著者の返信

### 論点 1: 非同期コンテキスト伝播（juner）

- 指摘: ブラウザには `await` をまたいで Context を保持する標準機構がない。TC39 の [AsyncContext proposal](https://github.com/tc39/proposal-async-context) に期待。
- 著者の返信: SIG（仕様策定チーム）も認識済み。Zone.js に依存しない実装を検討中で、issue #210 を参照予定。

### 論点 2: パフォーマンス／プライバシー（mizchi）

- 指摘: 「ブラウザパフォーマンスの文脈を欠いた実装に見える」「プライバシー面の懸念」。
- 著者・関係者の返信:
  - Resource Timing 実装はキューイングや `requestIdleCallback` を用いており、実装レビューに基づいた評価を促す。
  - プライバシー面では **URL の sanitization が opt-in である**など、具体的な改善対象を列挙。

### 検証コードの公開先

- `github.com/nissy-dev/sandbox/tree/main/otel-browser-sample`

---

## 7. 用語コラム（初見の用語を補足）

### 計装 (instrumentation)

「測定」そのものではなく、**アプリの動作に観測用コードを仕込むこと**。仕込みの結果としてテレメトリが出る。

| 種類 | 誰が観測コードを書くか | 例 |
| --- | --- | --- |
| 自動計装 (auto-instrumentation) | ライブラリが既存 API（`fetch` 等）を横取り（フック） | `instrumentation-fetch` |
| 手動計装 (manual instrumentation) | 開発者が「ここを測れ」と自分で書く | 独自処理を Span で囲む |

例: `instrumentation-fetch` を入れると、アプリが `fetch()` を呼ぶたびにその呼び出しを横取りし、開始・終了・URL・ステータスを Span として自動出力する。アプリ側コードの書き換えは不要。

### テレメトリ（traces / metrics / logs）

OpenTelemetry が扱う 3 種類の信号。

| 信号 | 内容 |
| --- | --- |
| traces（トレース） | 処理の流れ。Span の連なりで「どこで時間がかかったか」を追う |
| metrics（メトリクス） | 数値の集計（リクエスト数、レイテンシ分布など） |
| logs（ログ） | 個々の出来事の記録 |

### Span と LogRecord

第 2 章の表を参照。要点は「**Span は期間（開始〜終了）と親子を持つ／LogRecord は一瞬の点**」。

### OTLP と Exporter

- **OTLP (OpenTelemetry Protocol)**: テレメトリを送るための標準データ形式・通信プロトコル。HTTP 版が OTLP/HTTP。
- **Exporter**: 収集したテレメトリを外部（Collector 等）へ**送り出す部品**。`OTLPTraceExporter` は Span を、`OTLPLogExporter` は LogRecord を OTLP で送る。
- 参考: このリポジトリの backend も `OTEL_TRACES_EXPORTER=otlp` / `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf` を設定している（`ecspresso/_common.libsonnet`）。

### RUM (Real User Monitoring)

- **実際のユーザーのブラウザ上**で起きたことを計測する監視手法。
- 対義語は合成監視（Synthetic Monitoring）= 監視用ボットが定期アクセスして測る方式。
- RUM は本物のユーザー・実回線・実端末での体験を集めるため、実際の遅さやエラーが分かる。Sentry / Datadog のフロント監視がこれに当たる。

### Core Web Vitals

Google が定めたページ体験の代表指標。ブラウザ SDK では LogRecord（一瞬のスコア）として送られる。

| 指標 | 正式名 | 何を測るか |
| --- | --- | --- |
| LCP | Largest Contentful Paint | メインコンテンツ表示までの時間 |
| INP | Interaction to Next Paint | 操作 → 画面反応までの時間 |
| CLS | Cumulative Layout Shift | 表示中のレイアウトのズレ量 |

参考: [web.dev / Web Vitals](https://web.dev/articles/vitals)

### コンテキスト伝播 (context propagation) と AsyncContext

- **Context**: OpenTelemetry が裏で保持する「いま自分はどの Span の中にいるか（現在アクティブな Span）」。新しい子 Span を作るときにこれを見て親子を繋ぐ。
- **問題**: JavaScript は `await` の前後で実行が中断・再開するため、再開後に Context を見失い、Span の親子が切れることがある。
- **backend (Node.js)**: `AsyncLocalStorage`（`async_hooks`）という標準機構が Context を持ち回るため繋がりやすい。
- **ブラウザ**: 標準の相当機構がない。代替策:

| 手段 | 中身 | 弱点 |
| --- | --- | --- |
| Zone.js | 非同期 API 群を書き換えて Context を持ち回る | 全 API にパッチ = 重い・侵襲的 |
| AsyncContext proposal | TC39 で標準化検討中の言語仕様（将来の本命） | 未標準化 |
| unctx | 軽量なコンテキスト保持ライブラリ | 万能ではない |

### LGTM スタック

Grafana Labs の可観測性スタックの通称。

| 文字 | 製品 | 役割 |
| --- | --- | --- |
| L | Loki | ログ |
| G | Grafana | 可視化 UI |
| T | Tempo | トレース |
| M | Mimir | メトリクス |

記事の検証環境で使う `grafana/otel-lgtm` は、Collector と LGTM をまとめた検証用イメージ。

### requestIdleCallback

ブラウザがアイドル（暇）な時間にコールバックを実行する Web API。メインの描画・操作を邪魔しないよう、計装の重い処理をアイドル時間に回すために使われる。

---

## 8. このリポジトリとの関係

- 現状このリポジトリは **backend のみ** OpenTelemetry を計装（ADOT Collector サイドカー）。フロントエンドのエラー監視は Sentry を使用（`docs/monitoring/sentry-error-monitoring.md`）。
- もしフロントにも OpenTelemetry Browser SDK を導入するなら:
  1. Collector をブラウザから到達可能な**公開エンドポイント**として用意する（サイドカーの localhost では届かない）。
  2. **CORS の許可オリジン**を設計する。
  3. `session.id` 付与や `ignoreUrls`（Collector URL の除外）を設定する。
- ただし記事どおり Browser SDK の多くは experimental 段階であり、Session Replay / ソースマップ復元は未成熟。現時点では Sentry 併用が現実的。

---

## 参考リンク

- 対象記事: https://zenn.dev/cybozu_frontend/articles/opentelemetry-browser-frontend
- OpenTelemetry 公式: https://opentelemetry.io/
- OpenTelemetry JS: https://opentelemetry.io/docs/languages/js/
- OTLP 仕様: https://opentelemetry.io/docs/specs/otlp/
- Core Web Vitals: https://web.dev/articles/vitals
- TC39 AsyncContext proposal: https://github.com/tc39/proposal-async-context
- 検証コード: https://github.com/nissy-dev/sandbox/tree/main/otel-browser-sample
