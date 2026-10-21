# PHP・Webサーバーのセキュリティ更新手順書（WordPress + nginx／Apache、EC2／ConoHa）

Oct 21, 2026 · @masanori

## この手順書について

WordPressを動かしているサーバーで、**PHPとWebサーバー（nginx／Apache）のパッケージを更新し、新しいバイナリで動かし直す**ための手順です。

- **対象**：PHP（php-fpm／mod\_php）、nginx、Apache
- **対象外**：WordPress本体・テーマ・プラグイン、OS全体（カーネルなど）の更新
- **想定する構成**：EC2、ConoHa VPS、ConoHa WING × nginx／Apache × apt系／dnf系のOS

PHP本体の脆弱性（例：php2shell）は、WordPressのコードが1行も動く前に起きます。そのため**WordPressの管理画面で更新しても直りません**。サーバー側のPHPを更新する必要があります。理由の詳細は[php2shellのノート](./php2shell-and-nginx-2026-10.md)を参照してください。

各コマンドが何をしているかの詳しい解説は、[更新手順書のコマンド解説](./php-webserver-update-commands-explained.md)にまとめています。

### バージョン番号の置き換えについて

コマンドの例は**PHP 8.2**で書いています。コマンドの中の`8.2`は、[0-5](#0-5-phpのバージョンと入手元を確認する)で確認した**自分のサーバーのPHPの系列（`8.1`、`8.3`など）に置き換えてください**。置き換える箇所は、各コマンドの直前のコメントに`↓`で示しています。

### 全体の流れ

```
0. 構成を見分ける      … どの手順を使うかを決める
1. バックアップを取る   … 失敗したときに戻せるようにする
2. パッケージを更新する … ディスク上のファイルを新しくする
3. 再起動する          … 動いているプロセスを新しいバイナリに入れ替える
4. 確認する            … 新しいバージョンで動いているか、サイトが表示されるか
5. 切り戻す（失敗時）
```

2と3は両方とも必要です。`apt`／`dnf`が新しくするのは**ディスク上のファイルだけ**で、起動済みのプロセスは古いバイナリをメモリに読み込んだまま動き続けます。再起動しない限り、脆弱なままです。

### 複数台を作業するときの記録表

1台ずつ埋めながら進めると、漏れや二重作業を防げます。

| サーバー | クラウド | OS | Web | PHPの動かし方 | バックアップ | 更新前のPHP | 更新後のPHP | 確認 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| （例）web-01 | EC2 | Ubuntu 22.04 | nginx | php-fpm | AMI取得済み | 8.2.34 | 8.2.35 | OK |

---

## 0. 構成を見分ける

### 0-1. ConoHa VPS か ConoHa WING か（ConoHaの場合）

| 見分け方 | ConoHa VPS | ConoHa WING |
| --- | --- | --- |
| コントロールパネル | 「VPS」のメニュー | 「WING」のメニュー（サイト管理など） |
| SSHでrootになれるか | なれる | なれない |
| `apt`／`dnf`が使えるか | 使える | 使えない |

**ConoHa WINGの場合は、この先のコマンド手順は使いません。**[付録：ConoHa WINGの場合](#付録conoha-wingの場合)へ進んでください。

EC2とConoHa VPSは、サーバーにSSHで入ってからの手順は同じです。違うのはバックアップの取り方（[1章](#1-バックアップを取る)）だけです。

### 0-2. OSを確認する

```bash
# OSの種類とバージョンを表示する
# ID=ubuntu / debian → apt系、ID=amzn / almalinux / rocky → dnf系
cat /etc/os-release
```

rootでなくても実行できます。理由は[解説の1章](./php-webserver-update-commands-explained.md#1-osの情報etcos-release)を参照してください。

| `ID` | OS | パッケージ管理 |
| --- | --- | --- |
| `ubuntu`、`debian` | Ubuntu、Debian | apt系 |
| `amzn` | Amazon Linux 2023 | dnf系 |
| `almalinux`、`rocky` | AlmaLinux、Rocky Linux | dnf系 |

### 0-3. Webサーバーを確認する

```bash
# どのWebサーバーが動いているかを調べる（active と表示されたものが動いている）
# apache2 はapt系、httpd はdnf系でのApacheのサービス名
systemctl is-active nginx apache2 httpd
```

`inactive`は「止まっている」と「そのサービスがない」の両方を意味します。`active`の行を探してください。systemdを通さずに動かしている場合など、これで判別できないときの確かめ方は[解説の2章](./php-webserver-update-commands-explained.md#2-systemdとsystemctl)を参照してください。

### 0-4. PHPの動かし方を確認する

PHPの動かし方は3通りあり、再起動する対象が変わります。

| 構成 | PHPが動く場所 | 再起動する対象 |
| --- | --- | --- |
| nginx + php-fpm | php-fpm（nginxとは別のプロセス） | php-fpm |
| Apache + php-fpm | php-fpm（Apacheとは別のプロセス） | php-fpm |
| Apache + mod\_php | Apacheのプロセスの中 | Apache |

nginxはPHPを自分の中に組み込めないので、**nginxなら必ずphp-fpm**です。Apacheの場合は次のコマンドで見分けます。

```bash
# Apacheに読み込まれているモジュールの中からPHP関連を探す
# php_module（php7_module など）が出たら mod_php
# proxy_fcgi_module だけが出たら php-fpm 経由
# apt系：
sudo apache2ctl -M | grep -Ei 'php|proxy_fcgi'
# dnf系：
sudo httpd -M | grep -Ei 'php|proxy_fcgi'
```

mod\_phpとphp-fpmの違いは[解説の4章](./php-webserver-update-commands-explained.md#4-mod_phpとphp-fpm)を、`apache2ctl`と`httpd`の違いは[解説の3章](./php-webserver-update-commands-explained.md#3-apacheのコマンドapache2httpdapache2ctl)を参照してください。

```bash
# php-fpmのサービスがあるかを調べる。サービス名はこの後の再起動で使うので控えておく
# 例：php8.2-fpm.service（apt系）、php-fpm.service（dnf系）、php82-php-fpm.service（Remi）
systemctl list-units --type=service --all | grep -i fpm
```

### 0-5. PHPのバージョンと入手元を確認する

```bash
# CLIのPHPのバージョンを表示する
# php-fpmとは別のバイナリなので、php-fpmのバージョンは下のコマンドで別に確認する
php -v

# php-fpmのバージョンを表示する
# apt系：
# ↓ 「8.2」を0-4で控えたサービス名の数字に置き換える（php8.1-fpm なら php-fpm8.1）
php-fpm8.2 -v
# dnf系（コマンド名にバージョンは付かない）：
php-fpm -v
```

```bash
# apt系：インストール済みのPHPパッケージを表示する
# この出力で、使っているPHPの系列（php8.2-fpm なら 8.2）がわかる
dpkg -l 'php*' | grep ^ii

# apt系：そのパッケージの入手元のリポジトリを表示する
# ppa.launchpadcontent.net/ondrej と出たら ondrej PPA、archive.ubuntu.com などならOS標準
# ↓ 「8.2」を、すぐ上の dpkg -l で確認した系列に置き換える
apt-cache policy php8.2-fpm

# dnf系：インストール済みのPHPパッケージと入手元を表示する
# 右端の列が入手元（@amazonlinux、@appstream ならOS標準、@remi... ならRemi）
dnf list installed 'php*'
```

ここで確認した系列が**8.1以前**の場合は、先に[付録：修正版が出ていないバージョンの場合](#付録修正版が出ていないバージョンの場合)を確認してください。

各コマンドの違いと、OS標準・PPA・Remiの違いは[解説の6章](./php-webserver-update-commands-explained.md#6-パッケージ管理の仕組みdpkgaptrpmdnf)と[7章](./php-webserver-update-commands-explained.md#7-リポジトリos標準ondrej-pparemi)を参照してください。

入手元によって、修正版の届き方が違います。

- **ondrej PPA、Remi**：php.netの新しいバージョン（例：8.2.35）がそのまま届くことが多い
- **OS標準のパッケージ**：古いバージョンに修正だけを移植する（**バックポート**）ことが多い。そのため`php -v`が8.2.35にならなくても修正済みのことがある。判断方法は[4-3](#4-3-脆弱性が直っているかを確認する)を参照

nginxも同じで、OS標準のnginxはバックポートで直ることがあります。

---

## 1. バックアップを取る

**原則として必須です。** PHPを更新すると拡張モジュールの依存関係が変わることがあります。その結果php-fpmが起動しなくなり、サイトが502エラーになることがあります。そうなったときに、丸ごと元の状態に戻せるようにしておきます。

### EC2：AMIを作成する

AWSコンソールで、EC2 → インスタンス → 対象を選択 → アクション → イメージとテンプレート → イメージを作成。

- **「再起動しない」（No reboot）にチェックを入れる**。チェックしないと、AMI作成時にインスタンスが再起動されます
- 作成の状態は「AMI」の一覧で確認できます。「使用可能」になるまで数分〜十数分かかります

### ConoHa VPS：イメージを保存する

コントロールパネルで、対象のサーバー → 「イメージ保存」。

- サーバーの**停止が必要な場合があります**。停止するとサイトも止まるので、時間帯に注意してください
- 自動バックアップを契約している場合は、直近のバックアップがあるかも確認しておきます

### 緊急時の例外

次の両方に当てはまる場合は、バックアップを省略してよいものとします。

- 悪用が確認されている、または悪用される可能性が高い重大な脆弱性への対応である（例：認証なしのRCE）
- バックアップに時間がかかる、またはサーバーの停止が必要で、すぐに取れない

### 更新前のバージョンを記録する（必ず行う）

バックアップを取った場合も省略した場合も、**更新前のパッケージのバージョンを記録**してください。パッケージ単位で戻すとき（[5-2](#5-2-パッケージを戻す)）に必要になります。

```bash
# 更新前のPHP・nginx・Apache関連パッケージの「名前 バージョン」を画面に表示する
# 出力をそのままコピーして、作業記録（記録表、チケットなど）に貼り付ける
# apt系：
dpkg -l 'php*' 'nginx*' 'apache2*' | grep ^ii | awk '{print $2, $3}'
# dnf系：
rpm -qa 'php*' 'nginx*' 'httpd*' | sort
```

- **手で書き写さず、コピー＆ペーストする**。バージョン番号が1文字違うと、切り戻しに使えません
- **貼り付け先はサーバーの外にする**。サーバーごと戻すことになっても消えないようにするためです

各部分の意味は[解説の9章](./php-webserver-update-commands-explained.md#9-作業前のバージョンの記録)を参照してください。

---

## 2. パッケージを更新する

### apt系（Ubuntu、Debian）

```bash
# パッケージの一覧（どのバージョンが配布されているかのカタログ）を最新にする
# この時点では何もインストールされない
sudo apt update

# 更新できるパッケージのうち、PHP・nginx・Apache関連だけを表示する
# 何も出なければ、まだ修正版が配布されていない
apt list --upgradable 2>/dev/null | grep -Ei 'php|nginx|apache2'

# インストール済みのPHP 8.2系のパッケージだけを、8.2系の中の最新のバージョンにする
# 「8.2」は今のバージョンではなく、パッケージ名の一部（php8.2-fpm、php8.2-mysql など）
# 8.3など別の系列に上がることはない
# --only-upgrade：入っていないパッケージは新しく入れない
# 'php8.2-*' をクォートで囲むのは、シェルが先にファイル名として展開するのを防ぐため
# ↓ 「8.2」を0-5で確認した系列に置き換える（例：8.1系なら 'php8.1-*'）
sudo apt install --only-upgrade 'php8.2-*'

# nginxを使っている場合：nginxを更新する
sudo apt install --only-upgrade nginx

# Apacheを使っている場合：Apacheを更新する
sudo apt install --only-upgrade apache2
```

**途中で画面が出た場合**：Ubuntu 22.04以降では、更新の途中で「Daemons using outdated libraries」（古いライブラリを使っているサービスを再起動するか）という画面が出ることがあります。Enterで既定のまま進めて構いません。どちらを選んでも、3章で必要なサービスを手動で再起動します。

**`'php8.2-*'`がエラーになる場合**：`dpkg -l 'php8.2*' | grep ^ii`で出たパッケージ名を、`sudo apt install --only-upgrade php8.2-fpm php8.2-cli php8.2-common ...`のように並べて指定します（`8.2`は自分の系列に置き換えます）。

`8.2`の意味や`--only-upgrade`の詳しい説明は[解説の8章](./php-webserver-update-commands-explained.md#8-更新のコマンド)を参照してください。

### dnf系（Amazon Linux 2023、AlmaLinux、Rocky Linux）

```bash
# PHP・nginx・Apache関連で、更新できるパッケージがあるかを表示する
# 何も出なければ、まだ修正版が配布されていない
sudo dnf check-update 'php*' 'nginx*' 'httpd*'

# インストール済みのPHP関連パッケージをすべて新しいバージョンにする
# dnf upgrade は入っていないパッケージは新しく入れない
# 'php*' はAmazon Linuxの php8.2-* やRemiの php82-* にも当てはまるので、置き換えは不要
sudo dnf upgrade 'php*'

# nginxを使っている場合：nginxを更新する
sudo dnf upgrade nginx

# Apacheを使っている場合：Apacheを更新する
sudo dnf upgrade httpd
```

---

## 3. 再起動する

パッケージによっては、更新と同時に自動で再起動されることがあります。ただし確実に入れ替えるため、**必ず手動でrestartします**。

数秒間、502／503エラーが出ることがあります。この手順書では、確実に新しいバイナリへ入れ替えることを優先し、`reload`（無停止の入れ替え）ではなく`restart`に統一しています。

### nginx + php-fpm、Apache + php-fpm の場合

```bash
# php-fpmを停止してから起動し直し、新しいバイナリで動かす
# apt系：
# ↓ 「php8.2-fpm」を0-4で控えたサービス名に置き換える（例：php8.1-fpm）
sudo systemctl restart php8.2-fpm
# dnf系（OS標準、Amazon Linux）：
sudo systemctl restart php-fpm
# dnf系（Remiの並行インストール方式）：
# ↓ 「php82」を0-4で控えたサービス名に合わせる（例：php81-php-fpm）
sudo systemctl restart php82-php-fpm
```

nginxやApacheを2章で更新した場合だけ、それらも再起動します。PHPだけを更新した場合は不要です。nginxやApacheはPHPを自分の中に持たず、php-fpmにリクエストを転送しているだけだからです。

```bash
# nginxの設定ファイルに文法エラーがないかを確認する
# エラーがあると restart 後に起動できずサイトが止まるので、必ず先に確認する
sudo nginx -t

# nginxを停止してから起動し直す
sudo systemctl restart nginx
```

### Apache + mod\_php の場合

PHPはApacheのプロセスの中で動いているので、**PHPを更新したらApacheを再起動します**。

```bash
# Apacheの設定ファイルに文法エラーがないかを確認する（Syntax OK と出ればよい）
# apt系：
sudo apache2ctl configtest
# dnf系：
sudo apachectl configtest

# Apacheを停止してから起動し直す。中に組み込まれたPHPも新しいものに入れ替わる
# apt系：
sudo systemctl restart apache2
# dnf系：
sudo systemctl restart httpd
```

---

## 4. 確認する

### 4-1. サービスが動いているかを確認する

```bash
# サービスの状態を表示する
# 「Active: active (running) since ...」の時刻が、3章で再起動した時刻になっていればよい
# ↓ 「php8.2-fpm」と「nginx」を、自分の構成のサービス名に置き換える
#   php-fpm：php8.1-fpm、php-fpm、php82-php-fpm など（0-4で控えたもの）
#   Webサーバー：nginx、apache2、httpd のどれか（0-3で active だったもの）
systemctl status php8.2-fpm nginx --no-pager
```

### 4-2. バージョンを確認する

```bash
# 更新後のバージョンを表示する。記録表の「更新後のPHP」に書く
php -v
# apt系：
# ↓ 「8.2」を自分の系列に置き換える（例：php-fpm8.1）
php-fpm8.2 -v
# dnf系（コマンド名にバージョンは付かない）：
php-fpm -v
```

### 4-3. 脆弱性が直っているかを確認する

- **ondrej PPA、Remiなど**：4-2のバージョンが、php.netが発表した修正版以上であればよい
- **OS標準のパッケージ（バックポート）**：バージョン番号では判断できません。パッケージの変更履歴にCVE番号が載っているかで確認します

```bash
# パッケージの変更履歴から、目的のCVE番号を探す。1行以上出れば修正が入っている
# ↓ 「CVE-2026-109618」を、対応している脆弱性のCVE番号に置き換える
# apt系：
# ↓ 「php8.2-fpm」の「8.2」を自分の系列に置き換える（例：php8.1-fpm）
zcat /usr/share/doc/php8.2-fpm/changelog.Debian.gz | grep CVE-2026-109618
# dnf系：
# ↓ 「php-fpm」を、dnf list installed 'php*' に出たphp-fpmのパッケージ名に置き換える
#   （例：Amazon Linuxなら php8.2-fpm、Remiの並行インストール方式なら php82-php-fpm）
rpm -q --changelog php-fpm | grep CVE-2026-109618
```

見つからない場合は、OSのセキュリティ情報（Ubuntu Security Notices、Debian Security Advisories、Amazon Linux Security Center、AlmaLinux／Rocky Linuxのエラータ）でCVE番号を検索し、修正済みのパッケージのバージョンを確認します。

### 4-4. サイトが表示されるかを確認する

```bash
# サイトのトップページにアクセスし、レスポンスのヘッダーだけを表示する
# 1行目が HTTP/1.1 200 や HTTP/2 200 ならよい（301／302のリダイレクトも正常）
# 502／503が続く場合は、php-fpm（またはApache）が起動できていない
curl -sI https://example.com/
```

- ブラウザでサイトを開き、WordPressの管理画面にログインできるかを確認する
- 管理画面の「ツール」→「サイトヘルス」→「情報」→「サーバー」で、PHPのバージョンが更新後のものになっているかを確認する

### 4-5. エラーログを確認する

```bash
# 直近50行のエラーログを表示する。更新後の時刻に新しいエラーが出ていないかを見る
# nginx：
sudo tail -n 50 /var/log/nginx/error.log
# Apache（apt系）：
sudo tail -n 50 /var/log/apache2/error.log
# Apache（dnf系）：
sudo tail -n 50 /var/log/httpd/error_log
# php-fpm（apt系）：
# ↓ 「8.2」を自分の系列に置き換える（例：php8.1-fpm.log）
sudo tail -n 50 /var/log/php8.2-fpm.log
# php-fpm（dnf系）：
sudo tail -n 50 /var/log/php-fpm/error.log
```

---

## 5. 切り戻す（失敗したとき）

### 5-1. まず原因を見る

```bash
# サービスが起動しなかった理由をログから表示する（直近50行）
# ↓ 「php8.2-fpm」を、起動しなかったサービスの名前に置き換える
#   （例：php8.1-fpm、php-fpm、apache2、httpd）
sudo journalctl -u php8.2-fpm -n 50 --no-pager
```

よくある原因は、拡張モジュールのバージョンの不一致（一部のパッケージだけが更新された）や、設定ファイルの書式の変更です。足りないパッケージを更新し直すだけで直ることも多いので、すぐに切り戻さずに一度確認します。

### 5-2. パッケージを戻す

1章で記録したバージョンに戻します。**脆弱なバージョンに戻すことになるので、あくまで一時的な対応です。**原因を直したら、改めて更新してください。

```bash
# apt系：「パッケージ名=バージョン」の形で、バージョンを指定してインストールし直す
# ↓ 次の2か所を置き換える
#   ・「php8.2-fpm」「php8.2-common」：1章で記録したパッケージ名（戻したいものを並べる）
#   ・「8.2.34-1ubuntu1」：1章で記録した、そのパッケージの更新前のバージョン（例として書いた値）
# PPAなどでは古いバージョンが配布されなくなっていることがあり、その場合は戻せない
sudo apt install php8.2-fpm=8.2.34-1ubuntu1 php8.2-common=8.2.34-1ubuntu1

# dnf系：PHP関連パッケージを1つ前のバージョンに戻す
sudo dnf downgrade 'php*'
```

戻したら、3章と同じ手順で再起動します。

### 5-3. サーバーごと戻す

パッケージ単位で戻せないときは、1章で取ったバックアップから戻します。

- **EC2**：EC2 → インスタンス → 対象を選択 → アクション → モニタリングとトラブルシューティング → ルートボリュームを置き換え、で作成したAMIを指定する。または、AMIから新しいインスタンスを起動して入れ替える
- **ConoHa VPS**：コントロールパネルで、保存したイメージからサーバーを復元する

どちらの方法でも、**バックアップを取った後に書き込まれたデータ（投稿、アップロードしたファイルなど）は失われます**。DBが同じサーバーにある場合は特に注意してください。

---

## 付録：修正版が出ていないバージョンの場合

php.netが修正版を出すのは、**サポート中の系列だけ**です。たとえばphp2shellの修正版（8.5.12、8.4.27、8.3.36、8.2.35）は、それぞれ8.5系、8.4系、8.3系、8.2系を使っている場合の修正版です。**8.1以前の系列には、php.netからは修正版が出ません。**

ただし、**OS標準のパッケージなら、OSベンダーがバックポートで修正を出すことがあります**。OSのサポートが続いている間は、そのOSに入っている古い系列のPHPもOSベンダーが直すからです（例：Ubuntu 22.04のOS標準のPHPは8.1）。

### 判断の流れ

```
0-5で確認した系列は？
├─ 8.2以上（サポート中の系列）
│    → この手順書のとおりに更新する。同じ系列の中の更新なので互換性の心配はほぼない
│
└─ 8.1以前
     │
     入手元は？（0-5で確認）
     ├─ OS標準で、OSのサポートが続いている
     │    → OSのセキュリティ情報でCVE番号を検索し、修正済みのパッケージが出ているかを確認する
     │      ├─ 出ている   → この手順書のとおりに更新する（4-3でCVE番号を確認）
     │      └─ まだ出ない → 下の「当面の緩和策」を行い、修正が出るのを待つ
     │
     └─ ondrej PPA／Remi、またはOSのサポートが終わっている
          → 修正は出ない見込み。下の「当面の緩和策」を行い、8.2以上への移行を計画する
```

OSのサポート状況とセキュリティ情報は、各ベンダーのページ（Ubuntu Security Notices、Debian Security Advisories、Amazon Linux Security Center、AlmaLinux／Rocky Linuxのエラータ）で確認します。

### 当面の緩和策（php2shellの場合）

修正版を当てられるまでの**一時的な対策**です。完全には防げない可能性があります（[php2shellのノート](./php2shell-and-nginx-2026-10.md)を参照）。

PHPの設定ファイル（php.ini）に次の1行を書き、PHPを再起動します。

```ini
session.upload_progress.enabled = 0
```

php.iniは、PHPの動かし方ごとに別のファイルです。**Webで使われているほうのファイルを変更してください**（CLI用を変えてもWebサイトには効きません）。

| 構成 | 変更するファイル | 再起動する対象 |
| --- | --- | --- |
| php-fpm（apt系） | `/etc/php/8.1/fpm/php.ini`（`8.1`は自分の系列） | php-fpm |
| mod\_php（apt系） | `/etc/php/8.1/apache2/php.ini`（`8.1`は自分の系列） | Apache |
| dnf系（OS標準） | `/etc/php.ini` | php-fpm、またはmod\_phpならApache |

```bash
# 設定が反映されているかを、Webで使われているPHPの設定ファイルから確認する
# 「session.upload_progress.enabled = 0」の行が出ればよい（先頭に ; が付いた行はコメントなので無効）
# ↓ ファイルのパスを、上の表で変更したファイルに置き換える
grep -n 'session.upload_progress.enabled' /etc/php/8.1/fpm/php.ini
```

### 8.2以上への移行について

8.1以前から8.2以上への移行は、**この手順書の対象外**です。パッケージの入れ替え（`php8.1-*`を消して`php8.2-*`を入れる）、php-fpmの設定やnginx／Apacheからの接続先の変更、WordPressのテーマやプラグインが新しいバージョンに対応しているかの確認が必要になります。別の作業として計画してください。

なお、php.netで開発中のバージョン（例：8.6のRC版）は本番で使うものではないので、移行先にはしません。

---

## 付録：ConoHa WINGの場合

ConoHa WINGはレンタルサーバーなので、PHPのパッケージ更新はConoHa側が行います。利用者はコマンドを実行しません。やることは次の3つです。

1. **ConoHaのお知らせ・メンテナンス情報を確認する**：脆弱性への対応状況が告知されているかを見る
2. **使っているPHPのバージョンを確認する**：コントロールパネルのPHP設定（サイト管理の中にあります。メニュー名は変わることがあります）で確認する。**8.1以前の場合は、公式の修正が出ないことがある**ので、サポート中のバージョンへの切り替えを検討する
3. **切り替えた場合はサイトを確認する**：[4-4](#4-4-サイトが表示されるかを確認する)と同じく、サイトの表示、管理画面へのログイン、サイトヘルスのPHPバージョンを確認する

PHPのバージョンを切り替えて問題が出た場合は、元のバージョンに戻すだけで切り戻せます。

---

## 例：php2shell（CVE-2026-109618／109619）の場合

脆弱性ごとに変わるのは、**どのバージョンなら修正済みか**の部分だけです。手順そのものは上と同じです。

| 項目 | 内容 |
| --- | --- |
| 修正版（php.net） | 8.5系→8.5.12、8.4系→8.4.27、8.3系→8.3.36、8.2系→8.2.35（2026年10月21日公開） |
| 8.1以前 | php.netからの修正は出ない。[付録：修正版が出ていないバージョンの場合](#付録修正版が出ていないバージョンの場合)の流れで判断する |
| 当面の緩和策 | `session.upload_progress.enabled = 0`（完全な対策ではない） |
| 特にリスクが高い構成 | Apache + mod\_php（PHP公式の発表より） |
| 4-3での確認 | `grep CVE-2026-109618`と`grep CVE-2026-109619`の両方が見つかること |

- PHP公式の発表：[PHP: News Archive - 2026](https://www.php.net/archive/2026.php)
- 脆弱性の仕組みと影響：[php2shellのノート](./php2shell-and-nginx-2026-10.md)
