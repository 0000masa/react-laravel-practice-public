> 📌 **前提**：npm も npx も **Node.js をインストールすると一緒に入る**コマンドです（npx は npm 5.2 以降に同梱）。本書は「同じ `np` で始まる2つの違い」を、**管理（npm）と実行（npx）**という役割の差から整理します。このプロジェクトのフロントエンド（`frontend/www`, React + Vite）と一部のバックエンド開発コマンドが両方を使っています（③で実例）。

# npm と npx の違い

## ① 結論（先に答え）

ひとことで言うと、**役割が違う**だけです。

- **npm = パッケージの「管理」**：入れる・消す・更新する・`package.json` の scripts を実行する・公開する。`npm install` は **`node_modules/` にダウンロードして“居座らせる”**。
- **npx = パッケージの「実行」**：コマンド（CLI ツール）を**その場で実行**する。ローカルに無ければ **一時的に取ってきて実行し、基本は残さない**。

> 🧰 **比喩**：npm は「**工具箱に工具をしまう／出す／整理する**」係。npx は「**その工具を実際に握って1回使う**」係。たまにしか使わない工具を工具箱に常備（global install）せず、必要なときだけ借りて使って返す——それが npx。

覚え方：**npm = manage（管理・常駐）／ npx = execute（実行・使い捨て）**。

---

## ② 仕組み

### (1) npm — パッケージ管理係

主な使い道：

```bash
npm install            # package.json の依存を node_modules/ に入れる
npm install axios      # 個別に追加（dependencies に記録）
npm ci                 # package-lock.json 通りにクリーンインストール（CI向け・再現性重視）
npm run dev            # package.json の "scripts" を実行
npm uninstall axios    # 消す
npm publish            # 自作パッケージを npm レジストリに公開
```

ポイントは **「ダウンロードして `node_modules/` に置き、居座らせる」**こと。一度入れた依存はプロジェクトに常駐し、`package.json`／`package-lock.json` に記録されて再現できます。

`npm install`（ローカル）と `npm install -g`（グローバル）の違いも重要：

- **ローカル**（`-g` なし）→ そのプロジェクトの `node_modules/` に入る。プロジェクト単位。
- **グローバル**（`-g`）→ システム共通の場所に入り、どこからでもコマンドとして呼べる。

### (2) npx — パッケージ実行係

最大の特徴は **「インストールせずに、その場で取ってきて1回実行できる」**こと。npx はコマンドを探すとき次の順で動きます：

1. まず**ローカルの `node_modules/.bin/`** に目的のコマンドがあればそれを実行
2. 無ければ **npm レジストリから一時取得**して実行 → 基本は残さない

```bash
npx create-react-app myapp   # 雛形作成ツールを“その場だけ”実行（常駐させない）
npx skills@latest add ...    # skills CLI を最新版で取得して即実行
```

- `@latest` のようにバージョン指定すれば、**毎回最新を取ってこられる**（古い global を抱え込まない）。
- 初回はレジストリから落とすので一瞬待つことがある（npx が「このパッケージを入れていい?」と確認することも）。

### (3) なぜ npx が要るのか（違いの肝）

`create-react-app` や `skills` のような **「たまにしか使わない一発ツール」** を、毎回 `npm install -g` で常駐させると——

- バージョンが古いまま固定されがち（`@latest` を都度取りたい）
- グローバルが汚れ、他プロジェクトと競合する

npx なら **「最新版を、その時だけ、入れっぱなしにせず実行」**できる。だから**雛形生成・セットアップ系の一発ツール**に向きます。

> 💡 補足：npm 7 以降の npx は内部的に `npm exec` のラッパーになっています。「ローカルにあればそれ、無ければ取ってくる」という挙動はここから来ています。

---

## ③ このプロジェクトでは

### npm を使っている場所

- **フロントエンドの npm scripts**（`frontend/www/package.json`）：`dev`(=vite) / `build`(=`tsc -b && vite build`) / `lint`(=eslint)。`npm run build` のように **`npm run` で scripts を実行**している。
- **CI / ローカルの `npm ci`**：`.github/workflows/s3-deploy-frontend.yml:51-52`、`.github/workflows/preview-create.yml:165`、`docker-compose.yml:119` で `npm ci && npm run build`。CI で `install` でなく **`ci` を使うのは「`package-lock.json` 通りにクリーンインストールして再現性を高める」**ため（preview-create.yml にもその旨のコメントがある）。

### npx を使っている場所

- **`composer dev` の中身が npx**：`backend/www/composer.json:64` の `dev` スクリプトは
  `npx concurrently -c ... "php artisan serve" "php artisan queue:listen ..." "php artisan pail ..." "npm run dev" ...`
  となっており、**`concurrently`（複数プロセスを並列起動するツール）を global install せず npx でその場実行**している。まさに「(3) なぜ npx が要るのか」の実例。
- **今回の skills インストール**：`npx skills@latest add mattpocock/skills ...`。skills CLI を常駐させず最新版で1回実行している（→ `grill-skills-doc.md` 02章）。

> 🔗 つながり：フロントは「**依存を `node_modules` に常駐させて使う**（npm）」、`composer dev` は「**たまに使う並列実行ツールをその場で呼ぶ**（npx）」。同じプロジェクト内に npm と npx の典型的な使い分けが両方そろっている。

---

## ④ 落とし穴・よくある誤解

- **「npx ＝ npm の新しい版」ではない**：別物。npm は管理、npx は実行。役割が違うので置き換え関係にはない。
- **npm run は npx 無しでローカルツールを呼べる**：`npm run lint`（中身は `eslint .`）は、npm が **`node_modules/.bin/` を PATH に通して**実行するため。だから scripts 内ではわざわざ `npx eslint` と書かなくてよい。`npx` がローカルツールに使われるのは、scripts 外のワンライナーで叩くときなど。
- **`npm install` と `npm ci` は別物**：`install` は `package.json` を見て解決し `lock` を更新しうる。`ci` は **`package-lock.json` を厳密に再現**し（lock が無い／ズレると失敗）、`node_modules` を消してから入れ直す。**CI では再現性のため `ci`** が定石（このプロジェクトもそうしている）。
- **npx はネットワーク前提のことがある**：レジストリから取ってくる場合、オフラインや初回は時間がかかる・確認が出る。CI で多用すると遅延要因にもなる。
- **そもそも Node.js が無いと使えない**：npm も npx も Node.js 同梱。OS 標準コマンドではない。

---

## 用語集

- **npm（Node Package Manager）** — Node のパッケージ管理ツール。依存の install/uninstall/update、scripts 実行、公開を担う
- **npx** — パッケージのコマンドをその場で実行するツール（npm 5.2+ 同梱）。ローカルに無ければ一時取得して実行
- **`node_modules/`** — install した依存パッケージが置かれるディレクトリ。ローカルインストールの実体
- **`package.json`** — プロジェクトの依存・scripts・メタ情報を記述するファイル
- **`package-lock.json`** — 依存の解決結果（正確なバージョン）を固定するロックファイル。再現性の要
- **npm scripts** — `package.json` の `"scripts"` に定義したコマンド。`npm run <名前>` で実行。実行時 `node_modules/.bin/` が PATH に入る
- **`npm ci`** — lock 通りにクリーンインストールするコマンド。`node_modules` を消して入れ直す。CI 向け
- **global install（`-g`）** — システム共通の場所にパッケージを入れ、どこからでもコマンドとして使えるようにすること
- **`npm exec`** — npm 7+ で npx の実体になっているサブコマンド。「ローカルにあればそれ、無ければ取得」の挙動を提供
- **レジストリ** — パッケージが公開・配布される場所（既定は npm 公式レジストリ）

## 関連コード / ドキュメント（自力で読む練習に）

- `frontend/www/package.json` — npm scripts（dev/build/lint）の定義
- `.github/workflows/s3-deploy-frontend.yml` / `.github/workflows/preview-create.yml` — CI での `npm ci && npm run build`
- `backend/www/composer.json`（`dev` スクリプト）— `npx concurrently` の実例
- `docker-compose.yml`（frontend サービス）— ローカルでの `npm ci` / `npm run dev`

## 理解度チェッククイズ（答えは自分の言葉でどうぞ）

1. `create-react-app` のような雛形ツールを `npm install -g` ではなく `npx` で実行するのは、どんな利点があるからでしょうか？
2. `npm run lint`（中身は `eslint .`）は、なぜ `npx eslint` と書かなくても eslint を実行できるのでしょうか？（ヒント：PATH と `node_modules/.bin/`）
3. CI のワークフローが `npm install` ではなく `npm ci` を使っているのはなぜでしょうか？`ci` は何を保証しますか？
4. このプロジェクトの `composer dev` が `concurrently` を `npm install -g` せずに `npx concurrently` で呼んでいるのは、npm/npx のどちらの思想に沿った選択でしょうか？
