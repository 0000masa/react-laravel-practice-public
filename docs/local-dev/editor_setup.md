# エディタ設定ガイド（VS Code）

別の PC でも同じ開発環境を再現できるように、VS Code の推奨拡張と最小限のワークスペース設定をリポジトリで管理しています。

- `.vscode/extensions.json` … 推奨拡張のリスト
- `.vscode/settings.json` … 拡張を実際に効かせるための設定
- `frontend/www/.prettierrc` … Prettier の設定（デフォルト）

## 前提：リポジトリのルートを開く

VS Code では **リポジトリのルート**（`react-laravel-practice-public/`）を開く前提です。`frontend/www` や `backend/www` を直接開くと、ルートの `.vscode/` が読まれず推奨通知も設定も効きません。

WSL 上のリポジトリを Windows の VS Code から開く場合は、Remote - WSL 経由で接続してください。

## 適用手順（新しい PC で）

1. VS Code でリポジトリのルートを開く
2. 「このワークスペースには推奨拡張機能があります」の通知から **「すべてインストール」** を選ぶ
   - 通知を閉じてしまった場合: 拡張機能ビューの検索欄に `@recommended` と入力すると一覧が出る
3. フロントエンドの依存をインストールする（Prettier 本体はここに入る）

   ```bash
   cd frontend/www && npm install
   ```

## 推奨拡張とその理由

| 拡張 | ID | 対象 |
| --- | --- | --- |
| Remote - WSL | `ms-vscode-remote.remote-wsl` | WSL 上のリポジトリを開く |
| Dev Containers | `ms-vscode-remote.remote-containers` | `docker-compose.yml` のコンテナ環境 |
| ESLint | `dbaeumer.vscode-eslint` | `frontend/www/eslint.config.js` |
| Prettier | `esbenp.prettier-vscode` | `frontend/www` の TS/JS/CSS |
| Tailwind CSS IntelliSense | `bradlc.vscode-tailwindcss` | `frontend/www/tailwind.config.js` |
| PHP Intelephense | `bmewburn.vscode-intelephense-client` | `backend/www`（Laravel 12 / PHP 8.2） |
| Terraform | `hashicorp.terraform` | `terraform/**/*.tf` |
| Jsonnet | `grafana.vscode-jsonnet` | `ecspresso/**/*.jsonnet`, `*.libsonnet` |
| Draw.io Integration | `hediet.vscode-drawio` | `drawio/*.drawio` |

## 選定基準

**このリポジトリの開発に必要なものだけを載せる。** リポジトリ内に対象ファイルが実在し、かつ他の拡張で代替できないものが対象です。

載せないもの:

- **個人の好み** — UI 言語パック、AI アシスタント（Claude Code / Copilot / ChatGPT）、スニペット集、エラー表示の装飾など。無くてもビルド・Lint の結果は変わらない。
- **アカウントや課金が要るもの** — 推奨通り入れてもそのままでは使えないため（例: Infracost）。
- **機能が重複するもの** — `hashicorp.terraform` があれば `.tf` の編集は足りる。
- **対象ファイルが無いもの** — 過去の別プロジェクトで入れた拡張など。

`unwantedRecommendations`（非推奨リスト）は使っていません。実害のある衝突が特定できておらず、このキーは「推奨に出さない」だけでインストール済み拡張を無効化しないためです。

## settings.json が持つ設定

リポジトリのルートを開くため、各拡張の設定ファイルがサブディレクトリにあることを明示しています。

| 設定 | 目的 |
| --- | --- |
| `eslint.workingDirectories` | ESLint 拡張に `frontend/www` を見に行かせる。これが無いとエディタ上に警告が出ない |
| `tailwindCSS.experimental.configFile` | Tailwind 拡張に設定ファイルの場所を教える |
| `[typescript]` 等の `editor.defaultFormatter` | 既定フォーマッタを Prettier に固定する。指定しないと PC ごとに別のフォーマッタが走る |
| `php.suggest.basic: false` | VS Code 内蔵の PHP 補完を止める（Intelephense と候補が二重に出る）。Intelephense 公式の推奨設定 |

`editor.formatOnSave` は**入れていません**。保存時の振る舞いは各自の設定に委ねます。

## 整形の責任分界

| 対象 | ツール | 設定の場所 |
| --- | --- | --- |
| `frontend/www` の TS / JS / CSS | Prettier | `frontend/www/.prettierrc`（デフォルト） |
| `backend/www` の PHP | Laravel Pint | `backend/www`（composer の require-dev） |
| YAML / JSON / Markdown / Terraform | 整形ツールなし（手書き） | — |

Prettier の適用範囲を frontend に閉じているのは、YAML（`.github/workflows` 12 ファイル）や Markdown（600 ファイル超）まで対象にすると、一度の整形で差分が巨大になりレビュー不能になるためです。

手動で整形する場合:

```bash
cd frontend/www
npx prettier --check "src/**/*.{ts,tsx,css}"   # 差分の確認だけ
npx prettier --write "src/**/*.{ts,tsx,css}"   # 実際に整形
```

`eslint-config-prettier` は導入していません。現在の ESLint 構成（`js.recommended` / `typescript-eslint.recommended` / `react-hooks` / `react-refresh`）にフォーマット系ルールが含まれず、Prettier と競合しないためです。将来 stylistic 系のルールを追加する場合は、その時点で必要になります。

## 参考資料

- [Workspace recommended extensions（VS Code 公式）](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace#_workspace-recommended-extensions)
- [Prettier - Configuration File](https://prettier.io/docs/configuration)
- [Intelephense（Marketplace）](https://marketplace.visualstudio.com/items?itemName=bmewburn.vscode-intelephense-client)
- [ローカル環境の環境変数設定](environment_setup.md)
