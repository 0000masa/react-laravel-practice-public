# grill-me / grill-with-docs — Claude Code スキル解説（発表用ノート）

> コードを 1 行書く前に、Claude に「設計の穴」を質問攻めで突かせる。
> Matt Pocock が公開した一連のスキル（`grill-me` / `grill-with-docs` と、その中核 `grilling` / `domain-modeling`）の
> 出典・構成・原文・和訳・使い方をまとめた一枚ドキュメント。

| 項目 | 内容 |
| --- | --- |
| 作者 | Matt Pocock（元 Vercel エンジニア） |
| ライセンス | MIT |
| リポジトリ | `mattpocock/skills` |
| 対象 | Claude Code / Cowork |

---

## 01. これは何か

AI コーディングの失敗の多くは、モデルがコードを書けないからではなく、**要件が最後まで言語化されていない**まま実装に入ってしまうことで起きる。

`grill-me` はこの問題に対して、「いきなり計画を立てて走り出す」のではなく、**1 問ずつ質問を投げて設計判断を 1 つずつ確定させていく**という振る舞いを Claude に取らせるスキル。

ここでいう「skill」とは Claude Code に渡す短い振る舞い指示書（Markdown）のことで、`SKILL.md` という 1 ファイルが本体。設計の発想は書籍 *The Design of Design* に着想を得ているとされる。

現在の構成では、**「入口」スキルと「中身（エンジン）」スキルが分離**されている。`grill-me` / `grill-with-docs` は入口にすぎず、実際の処理は `grilling` と `domain-modeling` が担う（詳細は 03 章）。

> **セッションの規模感:** 1 回のセッションでおよそ **16〜50 問**。よく定義された小機能なら下限近く、業務フロー全体のような大きなテーマなら上限を超え、1 時間以上に及ぶこともある。

---

## 02. 出典とインストール

リポジトリ説明は *“Skills for Real Engineers. Straight from my .claude directory.”*（現役エンジニアの `.claude` ディレクトリそのまま）。MIT ライセンスで公開されている。

- **リポジトリ:** <https://github.com/mattpocock/skills>
- **grill-me:** `skills/productivity/grill-me/SKILL.md`
- **grilling:** `skills/productivity/grilling/SKILL.md`
- **grill-with-docs:** `skills/engineering/grill-with-docs/SKILL.md`
- **domain-modeling:** `skills/engineering/domain-modeling/SKILL.md`（`CONTEXT-FORMAT.md` / `ADR-FORMAT.md` を同梱）

### 推奨インストールコマンド（4スキルをまとめて）

対話プロンプトを使わず、Claude Code のプロジェクト直下（`.claude/skills/`）に必要な4スキルだけを入れる:

```bash
npx skills@latest add mattpocock/skills -a claude-code -y \
  --skill grill-me --skill grill-with-docs --skill grilling --skill domain-modeling
```

| オプション | 意味 | なぜ付けるか |
| --- | --- | --- |
| `-a claude-code` | 対象を Claude Code に限定 | 付けないと `.agents/skills/`（全エージェント共通の置き場）に入り、検出された多数のエージェントへ一括配置されてしまう。`.claude/skills/` だけに入れたいので必須 |
| `-y` | 対話プロンプトを全てスキップ（非対話） | 後述のターミナル表示崩れを回避するため |
| `--skill <名前>` | 入れるスキルを指定（繰り返し可） | これが無いと**全 36 スキルが入る**（`-y` は「プロンプトを飛ばす」だけで「全部入れる」の意味）。必要な4つだけに限定する |

> グローバル（どのプロジェクトでも使える `~/.claude/skills/`）に入れたい場合は末尾に `-g` を足す。上記はチーム共有・リポジトリ同梱を想定したプロジェクト直下インストール。

#### なぜ対話プロンプトだと表示が崩れるのか

このインストーラの対話 UI（スピナーや選択リスト）は、**ANSI エスケープシーケンス**で「カーソルを上に戻す → その行を消す → 描き直す」を毎フレーム繰り返して画面を更新する TUI（ターミナル UI）方式。矢印キーで選択を動かすたびに、リスト全体を消して再描画している。

ところが一部のターミナル——WSL や、IDE 組み込みのターミナル、ターミナル多重化（tmux 等）、あるいは報告される画面幅・高さがずれている環境——では、この「前のフレームを消す」エスケープシーケンスが正しく解釈されない。結果、**古い描画が消えずに残り、選択リストが2重・3重に表示される**といった崩れが起きる。

`-y` を付けると対話 UI 自体を出さず（＝再描画を一切しない）に処理が進むため、この崩れが原理的に起こらない。だから「選択リストがバグる環境では `-y` ＋ `--skill` でスキルを直接指定する」のが安全。

> ⚠️ **依存関係に注意:** `grill-me` / `grill-with-docs` は中身を委譲しているだけなので**単体では動かない**。`grill-me` には `grilling` を、`grill-with-docs` には `grilling` ＋ `domain-modeling` を併せて入れる必要がある（上のコマンドは4つとも入れているのでOK）。

> セットアップ補助の `/setup-matt-pocock-skills`（issue tracker や docs 保存先の初期設定）も使いたい場合は `--skill setup-matt-pocock-skills` を足す。

---

## 03. 4 スキルの構成（重要）

入口（ユーザーが打つ slash コマンド）と、実処理を行うエンジンが分かれている。

```text
grill-me          ──▶ grilling
grill-with-docs   ──▶ grilling ＋ domain-modeling
```

| スキル | 役割 | 中身 |
| --- | --- | --- |
| **`grill-me`** | 入口（薄いシム） | 本文は「`/grilling` を実行せよ」だけ |
| **`grill-with-docs`** | 入口（薄いシム） | 本文は「`/domain-modeling` を使って `/grilling` を実行せよ」だけ |
| **`grilling`** | 中核エンジン | 「質問攻め」の本体。設計ツリーを枝ごとに降り、判断を 1 つずつ確定させる |
| **`domain-modeling`** | 土台エンジン | 用語集（`CONTEXT.md`）と ADR を作る／研ぐ。曖昧な言葉を正規の用語に整える |

### この設計のポイント

- **DRY（重複排除）:** 「質問攻め」のロジックを `grilling` に 1 本化し、`grill-me` / `grill-with-docs` はそれを呼ぶだけにした。以前は同じ文面が各スキルにインラインで重複していた。
- **合成:** `grill-with-docs` ＝ `grilling`（詰める）＋ `domain-modeling`（用語・ADR を整える）の組み合わせ。エンジンを部品として組み合わせている。
- **`disable-model-invocation: true`:** `grill-me` / `grill-with-docs`（入口）に付いており、**ユーザーが明示的に呼んだときだけ発火**する（Claude が勝手に自動起動しない）。一方 `grilling` / `domain-modeling` には付いていないので、他スキルや状況から呼ばれ得る。

---

## 04. grill-me — 原文と和訳

入口スキル。中身は frontmatter ＋ 1 行だけ。

**Original (EN)**

> ```
> ---
> name: grill-me
> description: A relentless interview to sharpen a plan or design.
> disable-model-invocation: true
> ---
>
> Run a `/grilling` session.
> ```

**日本語訳**

> - **description:** 計画や設計を研ぎ澄ますための、容赦ない尋問。
> - **disable-model-invocation: true** — モデルによる自動発火を無効化（ユーザーが明示的に呼んだときだけ動く）。
> - **本文:** 「`/grilling` セッションを実行せよ。」

---

## 05. grill-with-docs — 原文と和訳

入口スキル。`grilling` に加えて `domain-modeling` を使う点だけが grill-me と違う。

**Original (EN)**

> ```
> ---
> name: grill-with-docs
> description: A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go.
> disable-model-invocation: true
> ---
>
> Run a `/grilling` session, using the `/domain-modeling` skill.
> ```

**日本語訳**

> - **description:** 計画や設計を研ぎ澄ますための容赦ない尋問。進めながら docs（ADR と用語集）も作っていく。
> - **本文:** 「`/domain-modeling` スキルを使いながら、`/grilling` セッションを実行せよ。」

---

## 06. grilling — 原文と和訳（中核エンジン）

「質問攻め」の本体。以前 grill-me / grill-with-docs に直接書かれていた指示文が、ここへ 1 本化された。

**Original (EN)**

> Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.
>
> Ask the questions one at a time, waiting for feedback on each question before continuing. Asking multiple questions at once is bewildering.
>
> If a question can be answered by exploring the codebase, explore the codebase instead.

**日本語訳**

> この計画のあらゆる側面について、共通理解に到達するまで容赦なく私を尋問せよ。設計ツリーの各枝を降りていき、判断どうしの依存関係を 1 つずつ解消していくこと。各質問について、あなたの推奨する答えも併せて提示すること。
>
> 質問は 1 つずつ行い、各質問への返答を待ってから次に進むこと。一度に複数の質問をするのは混乱を招く。
>
> コードベースを調べれば答えられる質問は、（私に聞くのではなく）コードベースを調べて答えること。

**frontmatter（description）の訳**

> 計画や設計についてユーザーを容赦なく尋問する。ユーザーが実装前に計画をストレステストしたいとき、あるいは「grill」系のトリガー語を使ったときに使用する。

---

## 07. domain-modeling — 原文と和訳（土台エンジン）

用語集（`CONTEXT.md`）と ADR を**能動的に作り・研ぐ**ためのスキル。`CONTEXT.md` を読むだけ（受動）はこのスキルではなく、モデルを書き換える（能動）ときに使う、と明記されている。

> ℹ️ **訳について（この節のみ要約抜粋）:** domain-modeling の `SKILL.md` は他の3スキルより長いため、本節は**全文訳ではなく要約抜粋**。具体的には frontmatter（description）と「During the session（セッション中の進め方）」各見出しの要旨を訳しており、**`File structure`（単一／複数コンテキストのディレクトリ構成図と、ファイルを遅延作成する方針）の節は省略**している。**`SKILL.md` の全文日本語対訳、および同梱の `CONTEXT-FORMAT.md` / `ADR-FORMAT.md` の全文対訳は [domain-modeling-translation.md](./domain-modeling-translation.md) を参照**（英語原文は[GitHub](https://github.com/mattpocock/skills/blob/main/skills/engineering/domain-modeling/SKILL.md)）。他の3スキル（grill-me / grill-with-docs / grilling）は短いため本書で全文訳。

**frontmatter（description）の訳**

> プロジェクトのドメインモデルを構築し研ぎ澄ます。ドメイン用語やユビキタス言語を確定させたいとき、アーキテクチャ上の決定を記録したいとき、あるいは他スキルがドメインモデルを保守する必要があるときに使う。

### セッション中の進め方（要約・和訳）

- **用語集と突き合わせる** — ユーザーの言葉が `CONTEXT.md` の既存定義と矛盾したら即指摘する。「用語集では cancellation を X と定義しているが、今は Y の意味で使っている。どちら？」
- **曖昧な言葉を研ぐ** — 多義的な語に正規の用語を提案。「『account』は Customer のこと？ User のこと？ 別物だ」
- **具体的なシナリオで検証する** — エッジケースを突くシナリオを作り、概念の境界を厳密に言わせる。
- **コードと相互参照する** — 「こう動く」と言われたらコードが同意するか確認し、矛盾を表に出す。
- **CONTEXT.md をその場で更新する** — 用語が確定した瞬間に更新。`CONTEXT.md` は実装の詳細を一切含まず、**用語集（glossary）に徹する**。
- **ADR は出し惜しむ** — 下記 3 条件がすべて成り立つときだけ作成を提案する。

### 補足: ADR とは

**ADR = Architecture Decision Record（アーキテクチャ決定記録）**。「**なぜその設計を選んだか**」を 1 件＝1 ファイルで残す軽量な記録のこと。

コードを読めば「**何を**」しているかは分かるが、「**なぜ**そうしたか」は残らない。ADR は、どんな文脈で・どんな代替案の中から・なぜそれを選んだかを書き留めておき、半年後の自分や後任が「なぜこうなってる？」で迷わないようにするためのもの。

実物はこれくらい短くてよい:

```text
# REST API を採用（GraphQL を見送り）
クライアントが少数で要件も安定しているため REST を採用。
GraphQL も検討したが、スキーマ運用の負荷に見合うメリットがないと判断した。
```

### ADR を提案する 3 条件

1. **覆すのが難しい** — 後で考えを変えるコストが大きい。
2. **文脈なしでは意外に映る** — 将来の読み手が「なぜこうした？」と疑問に思う。
3. **本物のトレードオフの結果である** — 実在する代替案があり、特定の理由でこれを選んだ。

3 つのうち 1 つでも欠けるなら ADR は作らない。同梱の `CONTEXT-FORMAT.md`（用語集の書式）と `ADR-FORMAT.md`（ADR は 1〜3 文で「文脈・決定・理由」を書く / `docs/adr/` に連番）に書式が定義されている。

---

## 08. 使い方

### インストールから 1 セッションまで

1. **インストール** — 02 章の推奨コマンド（`-a claude-code -y --skill ...`）で4スキルをまとめて入れる。手動で置く場合は各 `SKILL.md` を `.claude/skills/<name>/SKILL.md` に配置（依存先も忘れず）。
2. **呼び出す** — チャットで `/grill-me`（または `/grill-with-docs`）と打つ。後ろに題材を続けてもよい。入口スキルは `disable-model-invocation: true` なので、基本は**自分で明示的に呼ぶ**。
3. **1 問ずつ答える** — `grilling` が 1 問ずつ質問し、毎回「推奨する答え」も添えてくる。同意・修正・別案を返すと次の枝へ進む。コードで分かることは Claude が自分で調べる。
4. **共通理解に達したら実装へ** — 設計ツリーを降り切ったら、固まった要件をそのまま実装に渡す。`grill-with-docs` なら、過程で `domain-modeling` が `CONTEXT.md` / ADR を更新済みにしてくれる。

### ターミナルでの実行例

```text
# 題材を添えて起動
> /grill-me 検索ページを追加したい

# Claude（grilling が1問ずつ・推奨答え付き）
Q1. 検索は「単一テキストボックス」か「絞り込み付きの高度な検索」か？
    推奨: まずは単一ボックス（最小で出して反応を見る）
```

---

## 09. 要点 — なぜ「詰められる」と結果が良くなるのか

- **未決定を強制的に決定に変える** — 質問が、まだ下していない判断を言語化させる。「なんとなく」を残さない。
- **隠れた前提を表に出す** — 自分でも気づいていなかった思い込みが、質問によって浮かび上がる。
- **避けてきたトレードオフに向き合わせる** — 先送りにしていた選択を、実装前に決め切る。
- **1 問ずつ・推奨付き** — 一度に詰め込まないので思考が追える。推奨答えがあるので、ゼロから考えるより速く判断できる。
- **入口とエンジンの分離** — 「質問攻め(`grilling`)」と「用語・ADR 整備(`domain-modeling`)」を部品化し、入口スキルが組み合わせて呼ぶ。重複が消え、組み替えも効く。
- **たった数行の Markdown** — 高度な仕組みではなく「振る舞いの指示書」。だからこそ読めて、真似でき、自分用に改造できる。

---

*出典 / Source: <https://github.com/mattpocock/skills> · MIT License · Author: Matt Pocock*
*原文の引用と和訳は解説目的（発表用）。訳は本ドキュメント作成時のもの。*
