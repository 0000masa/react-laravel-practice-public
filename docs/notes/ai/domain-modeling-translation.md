> 📌 **これは何か**：Matt Pocock の `domain-modeling` スキルを構成する **3ファイルの全文対訳**（英語原文＋日本語訳）です。姉妹編 [grill-skills-doc.md](./grill-skills-doc.md) では `SKILL.md` を要約しか載せていない（FORMAT 2ファイルは未訳）ため、本書で全文を訳します。
>
> 対象ファイル（現在は `.claude/skills/domain-modeling/` 配下）：
> - `SKILL.md` — スキル本体
> - `CONTEXT-FORMAT.md` — 用語集（`CONTEXT.md`）の書式
> - `ADR-FORMAT.md` — ADR（アーキテクチャ決定記録）の書式
>
> 原文：<https://github.com/mattpocock/skills/tree/main/skills/engineering/domain-modeling> ／ MIT License ／ 訳は本書作成時のもの。

# domain-modeling スキル — 3ファイル全文対訳

`domain-modeling` は、`grill-with-docs` から呼ばれる「土台エンジン」。プロジェクトのドメインモデル（用語集と設計判断）を**能動的に作り・研ぐ**ためのスキルです。構成は次の3ファイル。

| ファイル | 役割 |
| --- | --- |
| `SKILL.md` | スキルの振る舞い本体（いつ・何をするか） |
| `CONTEXT-FORMAT.md` | 用語集 `CONTEXT.md` の書き方 |
| `ADR-FORMAT.md` | 設計判断記録 ADR の書き方 |

---

## 1. SKILL.md

### frontmatter

**Original (EN)**

> ```
> name: domain-modeling
> description: Build and sharpen a project's domain model. Use when the user wants to pin down domain terminology or a ubiquitous language, record an architectural decision, or when another skill needs to maintain the domain model.
> ```

**日本語訳**

> プロジェクトのドメインモデルを構築し、研ぎ澄ます。ドメイン用語やユビキタス言語を確定させたいとき、アーキテクチャ上の決定を記録したいとき、あるいは他のスキルがドメインモデルを保守する必要があるときに使う。

### 冒頭（スキルの定義）

**Original (EN)**

> # Domain Modeling
>
> Actively build and sharpen the project's domain model as you design. This is the *active* discipline — challenging terms, inventing edge-case scenarios, and writing the glossary and decisions down the moment they crystallise. (Merely *reading* `CONTEXT.md` for vocabulary is not this skill — that's a one-line habit any skill can do. This skill is for when you're changing the model, not just consuming it.)

**日本語訳**

> # ドメインモデリング
>
> 設計を進めながら、プロジェクトのドメインモデルを能動的に構築し、研ぎ澄ますこと。これは*能動的な*営みである——用語に異議を唱え、エッジケースのシナリオを考案し、用語集と決定事項を、それらが固まった瞬間に書き留める。（語彙を確認するために `CONTEXT.md` を*読むだけ*なら、それはこのスキルではない。それはどのスキルでもできる一行の習慣にすぎない。このスキルは、モデルを単に消費するのではなく、**変更する**ときのためのものだ。）

### File structure（ファイル構成）

**Original (EN)**

> Most repos have a single context:
>
> ```
> /
> ├── CONTEXT.md
> ├── docs/
> │   └── adr/
> │       ├── 0001-event-sourced-orders.md
> │       └── 0002-postgres-for-write-model.md
> └── src/
> ```
>
> If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:
>
> ```
> /
> ├── CONTEXT-MAP.md
> ├── docs/
> │   └── adr/                          ← system-wide decisions
> ├── src/
> │   ├── ordering/
> │   │   ├── CONTEXT.md
> │   │   └── docs/adr/                 ← context-specific decisions
> │   └── billing/
> │       ├── CONTEXT.md
> │       └── docs/adr/
> ```
>
> Create files lazily — only when you have something to write. If no `CONTEXT.md` exists, create one when the first term is resolved. If no `docs/adr/` exists, create it when the first ADR is needed.

**日本語訳**

> 多くのリポジトリは単一のコンテキストを持つ：
>
> ```
> /
> ├── CONTEXT.md
> ├── docs/
> │   └── adr/
> │       ├── 0001-event-sourced-orders.md
> │       └── 0002-postgres-for-write-model.md
> └── src/
> ```
>
> ルートに `CONTEXT-MAP.md` が存在するなら、そのリポジトリは複数のコンテキストを持つ。マップは各コンテキストの所在を指し示す：
>
> ```
> /
> ├── CONTEXT-MAP.md
> ├── docs/
> │   └── adr/                          ← システム全体の決定
> ├── src/
> │   ├── ordering/
> │   │   ├── CONTEXT.md
> │   │   └── docs/adr/                 ← そのコンテキスト固有の決定
> │   └── billing/
> │       ├── CONTEXT.md
> │       └── docs/adr/
> ```
>
> ファイルは遅延作成すること——書くべき中身ができたときにだけ作る。`CONTEXT.md` が無ければ、最初の用語が確定したときに作る。`docs/adr/` が無ければ、最初の ADR が必要になったときに作る。

> 💡 補足：このプロジェクトはルートに `CONTEXT-MAP.md`（AWS / GCP の複数コンテキスト）と `docs/adr/` を既に持つため、上の「複数コンテキスト構成」にそのまま当てはまる。

### During the session（セッション中の進め方）

#### Challenge against the glossary（用語集と突き合わせる）

**Original (EN)**

> When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

**日本語訳**

> ユーザーが `CONTEXT.md` の既存の言葉と矛盾する用語を使ったら、即座に指摘する。「あなたの用語集では 'cancellation' を X と定義しているが、今は Y の意味で使っているようだ——どちらが正しい？」

#### Sharpen fuzzy language（曖昧な言葉を研ぐ）

**Original (EN)**

> When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

**日本語訳**

> ユーザーが曖昧な、あるいは意味を詰め込みすぎた用語を使ったら、正確で標準的な用語を提案する。「あなたは 'account' と言っているが、それは Customer のことか、User のことか？ それらは別物だ。」

#### Discuss concrete scenarios（具体的なシナリオで議論する）

**Original (EN)**

> When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

**日本語訳**

> ドメインの関係性を議論しているときは、具体的なシナリオでそれをストレステストする。エッジケースを突くシナリオを考案し、概念どうしの境界についてユーザーに厳密な言明を迫る。

#### Cross-reference with code（コードと相互参照する）

**Original (EN)**

> When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

**日本語訳**

> ユーザーが「これはこう動く」と述べたら、コードがそれに同意しているか確認する。矛盾を見つけたら、それを表に出す。「あなたのコードは Order 全体をキャンセルしているが、今あなたは部分キャンセルが可能だと言った——どちらが正しい？」

#### Update CONTEXT.md inline（CONTEXT.md をその場で更新する）

**Original (EN)**

> When a term is resolved, update `CONTEXT.md` right there. Don't batch these up — capture them as they happen. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).
>
> `CONTEXT.md` should be totally devoid of implementation details. Do not treat `CONTEXT.md` as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

**日本語訳**

> 用語が確定したら、その場で `CONTEXT.md` を更新する。まとめて後回しにせず、起きたそばから書き留める。書式は [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md)（本書の §3）に従う。
>
> `CONTEXT.md` は実装の詳細を一切含んではならない。`CONTEXT.md` を仕様書・メモ帳・実装判断の置き場として扱ってはいけない。それは用語集であり、それ以外の何物でもない。

#### Offer ADRs sparingly（ADR は出し惜しんで提案する）

**Original (EN)**

> Only offer to create an ADR when all three are true:
>
> 1. **Hard to reverse** — the cost of changing your mind later is meaningful
> 2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
> 3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons
>
> If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).

**日本語訳**

> 次の3つがすべて成り立つときだけ、ADR の作成を提案する：
>
> 1. **覆すのが難しい** — 後で考えを変えるコストが大きい
> 2. **文脈なしでは意外に映る** — 将来の読み手が「なぜこのやり方にしたのか？」と疑問に思う
> 3. **本物のトレードオフの結果である** — 実在する代替案があり、特定の理由でそれを選んだ
>
> 3つのうち1つでも欠けるなら、ADR は作らない。書式は [ADR-FORMAT.md](./ADR-FORMAT.md)（本書の §2）に従う。

---

## 2. ADR-FORMAT.md

### 冒頭

**Original (EN)**

> # ADR Format
>
> ADRs live in `docs/adr/` and use sequential numbering: `0001-slug.md`, `0002-slug.md`, etc.
>
> Create the `docs/adr/` directory lazily — only when the first ADR is needed.

**日本語訳**

> # ADR の書式
>
> ADR は `docs/adr/` に置き、連番で命名する：`0001-slug.md`、`0002-slug.md`、など。
>
> `docs/adr/` ディレクトリは遅延作成する——最初の ADR が必要になったときにだけ作る。

### Template（テンプレート）

**Original (EN)**

> ```md
> # {Short title of the decision}
>
> {1-3 sentences: what's the context, what did we decide, and why.}
> ```
>
> That's it. An ADR can be a single paragraph. The value is in recording *that* a decision was made and *why* — not in filling out sections.

**日本語訳**

> ```md
> # {決定の短いタイトル}
>
> {1〜3文：どんな文脈で、何を決め、なぜそうしたか。}
> ```
>
> これで全部だ。ADR は一段落でよい。価値は、決定が下された*という事実*と*その理由*を記録することにある——セクションを埋めることにあるのではない。

### Optional sections（任意のセクション）

**Original (EN)**

> Only include these when they add genuine value. Most ADRs won't need them.
>
> - **Status** frontmatter (`proposed | accepted | deprecated | superseded by ADR-NNNN`) — useful when decisions are revisited
> - **Considered Options** — only when the rejected alternatives are worth remembering
> - **Consequences** — only when non-obvious downstream effects need to be called out

**日本語訳**

> 本当に価値が増すときだけ含める。ほとんどの ADR には不要だ。
>
> - **Status**（ステータス）の frontmatter（`proposed（提案中）| accepted（承認済み）| deprecated（非推奨）| superseded by ADR-NNNN（ADR-NNNN により置き換え）`）——決定が見直されるときに役立つ
> - **Considered Options**（検討した選択肢）——却下した代替案を覚えておく価値があるときだけ
> - **Consequences**（結果・影響）——自明でない波及効果を明示する必要があるときだけ

### Numbering（採番）

**Original (EN)**

> Scan `docs/adr/` for the highest existing number and increment by one.

**日本語訳**

> `docs/adr/` を見て既存の最大番号を探し、1 を足す。

### When to offer an ADR（いつ ADR を提案するか）

**Original (EN)**

> All three of these must be true:
>
> 1. **Hard to reverse** — the cost of changing your mind later is meaningful
> 2. **Surprising without context** — a future reader will look at the code and wonder "why on earth did they do it this way?"
> 3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons
>
> If a decision is easy to reverse, skip it — you'll just reverse it. If it's not surprising, nobody will wonder why. If there was no real alternative, there's nothing to record beyond "we did the obvious thing."

**日本語訳**

> 次の3つがすべて成り立たなければならない：
>
> 1. **覆すのが難しい** — 後で考えを変えるコストが大きい
> 2. **文脈なしでは意外に映る** — 将来の読み手がコードを見て「いったいなぜこんなやり方をしたのか？」と疑問に思う
> 3. **本物のトレードオフの結果である** — 実在する代替案があり、特定の理由でそれを選んだ
>
> 覆すのが簡単な決定なら、記録しない——どうせ覆すのだから。意外でないなら、誰も理由を疑問に思わない。本物の代替案が無かったなら、「当たり前のことをした」以上に記録すべきものは無い。

### What qualifies（何が ADR に値するか）

**Original (EN)**

> - **Architectural shape.** "We're using a monorepo." "The write model is event-sourced, the read model is projected into Postgres."
> - **Integration patterns between contexts.** "Ordering and Billing communicate via domain events, not synchronous HTTP."
> - **Technology choices that carry lock-in.** Database, message bus, auth provider, deployment target. Not every library — just the ones that would take a quarter to swap out.
> - **Boundary and scope decisions.** "Customer data is owned by the Customer context; other contexts reference it by ID only." The explicit no-s are as valuable as the yes-s.
> - **Deliberate deviations from the obvious path.** "We're using manual SQL instead of an ORM because X." Anything where a reasonable reader would assume the opposite. These stop the next engineer from "fixing" something that was deliberate.
> - **Constraints not visible in the code.** "We can't use AWS because of compliance requirements." "Response times must be under 200ms because of the partner API contract."
> - **Rejected alternatives when the rejection is non-obvious.** If you considered GraphQL and picked REST for subtle reasons, record it — otherwise someone will suggest GraphQL again in six months.

**日本語訳**

> - **アーキテクチャの形。**「モノレポを採用している。」「書き込みモデルはイベントソーシング、読み取りモデルは Postgres に射影している。」
> - **コンテキスト間の統合パターン。**「Ordering と Billing は同期 HTTP ではなくドメインイベントで通信する。」
> - **ロックインを伴う技術選定。** データベース、メッセージバス、認証プロバイダ、デプロイ先。あらゆるライブラリではなく、差し替えに四半期かかるようなものだけ。
> - **境界とスコープの決定。**「Customer のデータは Customer コンテキストが所有し、他のコンテキストは ID 経由でのみ参照する。」明示的な「やらないこと」は「やること」と同じくらい価値がある。
> - **自明な道からの意図的な逸脱。**「X という理由で、ORM ではなく手書き SQL を使っている。」分別ある読み手なら逆を想定するようなもの全般。これは次のエンジニアが「意図的だったもの」を“修正”してしまうのを防ぐ。
> - **コードからは見えない制約。**「コンプライアンス要件のため AWS は使えない。」「パートナー API の契約により、応答時間は 200ms 未満でなければならない。」
> - **却下した代替案（その却下が自明でないとき）。** GraphQL を検討したうえで微妙な理由から REST を選んだなら、記録する——さもないと半年後に誰かがまた GraphQL を提案してくる。

---

## 3. CONTEXT-FORMAT.md

### Structure（構造）

**Original (EN)**

> ```md
> # {Context Name}
>
> {One or two sentence description of what this context is and why it exists.}
>
> ## Language
>
> **Order**:
> {A one or two sentence description of the term}
> _Avoid_: Purchase, transaction
>
> **Invoice**:
> A request for payment sent to a customer after delivery.
> _Avoid_: Bill, payment request
>
> **Customer**:
> A person or organization that places orders.
> _Avoid_: Client, buyer, account
> ```

**日本語訳**（書式そのものは英語のまま使う前提で、各部の意味を訳す）

> ```md
> # {コンテキスト名}
>
> {このコンテキストが何で、なぜ存在するのかを1〜2文で説明。}
>
> ## Language（言語・用語）
>
> **Order**:
> {その用語の1〜2文の説明}
> _Avoid_（避ける語）: Purchase, transaction
>
> **Invoice**:
> 配送後に顧客へ送られる支払い請求。
> _Avoid_: Bill, payment request
>
> **Customer**:
> 注文を行う個人または組織。
> _Avoid_: Client, buyer, account
> ```

### Rules（ルール）

**Original (EN)**

> - **Be opinionated.** When multiple words exist for the same concept, pick the best one and list the others under `_Avoid_`.
> - **Keep definitions tight.** One or two sentences max. Define what it IS, not what it does.
> - **Only include terms specific to this project's context.** General programming concepts (timeouts, error types, utility patterns) don't belong even if the project uses them extensively. Before adding a term, ask: is this a concept unique to this context, or a general programming concept? Only the former belongs.
> - **Group terms under subheadings** when natural clusters emerge. If all terms belong to a single cohesive area, a flat list is fine.

**日本語訳**

> - **断定的であれ。** 同じ概念に複数の語が存在するなら、最良の1つを選び、残りを `_Avoid_` に列挙する。
> - **定義は引き締めておけ。** 最大でも1〜2文。それが「何をするか」ではなく「何で**ある**か」を定義する。
> - **このプロジェクトのコンテキストに固有の用語だけを含める。** 一般的なプログラミング概念（タイムアウト、エラー型、ユーティリティのパターン等）は、プロジェクトで多用していても載せない。用語を追加する前に問え——これはこのコンテキスト固有の概念か、それとも一般的なプログラミング概念か？ 前者だけが該当する。
> - **自然なまとまりが現れたら、用語を小見出しでグループ化する。** すべての用語が単一のまとまった領域に属するなら、フラットなリストでよい。

### Single vs multi-context repos（単一 vs 複数コンテキストのリポジトリ）

**Original (EN)**

> **Single context (most repos):** One `CONTEXT.md` at the repo root.
>
> **Multiple contexts:** A `CONTEXT-MAP.md` at the repo root lists the contexts, where they live, and how they relate to each other:
>
> ```md
> # Context Map
>
> ## Contexts
>
> - [Ordering](./src/ordering/CONTEXT.md) — receives and tracks customer orders
> - [Billing](./src/billing/CONTEXT.md) — generates invoices and processes payments
> - [Fulfillment](./src/fulfillment/CONTEXT.md) — manages warehouse picking and shipping
>
> ## Relationships
>
> - **Ordering → Fulfillment**: Ordering emits `OrderPlaced` events; Fulfillment consumes them to start picking
> - **Fulfillment → Billing**: Fulfillment emits `ShipmentDispatched` events; Billing consumes them to generate invoices
> - **Ordering ↔ Billing**: Shared types for `CustomerId` and `Money`
> ```

**日本語訳**

> **単一コンテキスト（ほとんどのリポジトリ）:** リポジトリのルートに `CONTEXT.md` を1つ。
>
> **複数コンテキスト:** ルートの `CONTEXT-MAP.md` が、コンテキストの一覧・所在・相互の関係を列挙する：
>
> ```md
> # Context Map
>
> ## Contexts（コンテキスト一覧）
>
> - [Ordering](./src/ordering/CONTEXT.md) — 顧客の注文を受け付け、追跡する
> - [Billing](./src/billing/CONTEXT.md) — 請求書を生成し、支払いを処理する
> - [Fulfillment](./src/fulfillment/CONTEXT.md) — 倉庫のピッキングと出荷を管理する
>
> ## Relationships（関係）
>
> - **Ordering → Fulfillment**: Ordering が `OrderPlaced` イベントを発行し、Fulfillment がそれを消費してピッキングを開始する
> - **Fulfillment → Billing**: Fulfillment が `ShipmentDispatched` イベントを発行し、Billing がそれを消費して請求書を生成する
> - **Ordering ↔ Billing**: `CustomerId` と `Money` の型を共有する
> ```

**Original (EN)**

> The skill infers which structure applies:
>
> - If `CONTEXT-MAP.md` exists, read it to find contexts
> - If only a root `CONTEXT.md` exists, single context
> - If neither exists, create a root `CONTEXT.md` lazily when the first term is resolved
>
> When multiple contexts exist, infer which one the current topic relates to. If unclear, ask.

**日本語訳**

> スキルは、どちらの構造が当てはまるかを推測する：
>
> - `CONTEXT-MAP.md` が存在するなら、それを読んでコンテキストを見つける
> - ルートに `CONTEXT.md` だけが存在するなら、単一コンテキスト
> - どちらも無ければ、最初の用語が確定したときにルートの `CONTEXT.md` を遅延作成する
>
> 複数のコンテキストが存在するときは、現在の話題がどのコンテキストに関係するかを推測する。判然としなければ、尋ねる。

---

*出典 / Source: <https://github.com/mattpocock/skills> · MIT License · Author: Matt Pocock*
*原文の引用と全文和訳は解説目的。訳は本書作成時のもの。関連: [grill-skills-doc.md](./grill-skills-doc.md)*
