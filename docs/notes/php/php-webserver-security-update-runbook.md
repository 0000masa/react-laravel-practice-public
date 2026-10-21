# PHP・Webサーバーのセキュリティ更新手順書（WordPress + nginx／Apache、EC2／ConoHa）

Oct 21, 2026 · @masanori

## この手順書について

WordPressを動かしているサーバーで、**PHPとWebサーバー（nginx／Apache）のパッケージを更新し、新しいバイナリで動かし直す**ための手順です。

- **対象**：PHP（php-fpm／mod\_php）、nginx、Apache
- **対象外**：WordPress本体・テーマ・プラグイン、OS全体（カーネルなど）の更新
- **想定する構成**：EC2、ConoHa VPS、ConoHa WING × nginx／Apache × apt系／dnf系のOS

PHP本体の脆弱性（例：php2shell）は、WordPressのコードが1行も動く前に起きます。そのため**WordPressの管理画面で更新しても直りません**。サーバー側のPHPを更新する必要があります。理由の詳細は[php2shellのノート](./php2shell-and-nginx-2026-10.md)を参照してください。

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

# php-fpmのバージョンを表示する（0-4で控えたサービス名に合わせる）
# apt系：
php-fpm8.2 -v
# dnf系：
php-fpm -v
```

```bash
# apt系：インストール済みのPHPパッケージと、その入手元のリポジトリを表示する
# ppa.launchpadcontent.net/ondrej と出たら ondrej PPA、archive.ubuntu.com などならOS標準
dpkg -l 'php*' | grep ^ii
apt-cache policy php8.2-fpm

# dnf系：インストール済みのPHPパッケージを表示する
# 右端の列が入手元（@amazonlinux、@appstream ならOS標準、@remi... ならRemi）
dnf list installed 'php*'
```

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

省略する場合でも、**更新前のパッケージのバージョンだけは必ず記録**してください。パッケージ単位で戻すとき（[5-2](#5-2-パッケージを戻す)）に必要になります。

```bash
# 更新前のパッケージのバージョンをファイルに保存する（ファイル名に日付を入れる）
# apt系：
dpkg -l 'php*' 'nginx*' 'apache2*' | grep ^ii > ~/packages-before-$(date +%Y%m%d).txt
# dnf系：
rpm -qa 'php*' 'nginx*' 'httpd*' | sort > ~/packages-before-$(date +%Y%m%d).txt
```

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

# インストール済みのPHP 8.2関連パッケージだけを新しいバージョンにする
# --only-upgrade：入っていないパッケージは新しく入れない
# 'php8.2-*' をクォートで囲むのは、シェルが先にファイル名として展開するのを防ぐため
# バージョン部分（8.2）は0-5で確認したものに合わせる
sudo apt install --only-upgrade 'php8.2-*'

# nginxを使っている場合：nginxを更新する
sudo apt install --only-upgrade nginx

# Apacheを使っている場合：Apacheを更新する
sudo apt install --only-upgrade apache2
```

**途中で画面が出た場合**：Ubuntu 22.04以降では、更新の途中で「Daemons using outdated libraries」（古いライブラリを使っているサービスを再起動するか）という画面が出ることがあります。Enterで既定のまま進めて構いません。どちらを選んでも、3章で必要なサービスを手動で再起動します。

**`'php8.2-*'`がエラーになる場合**：`dpkg -l 'php8.2*' | grep ^ii`で出たパッケージ名を、`sudo apt install --only-upgrade php8.2-fpm php8.2-cli php8.2-common ...`のように並べて指定します。

### dnf系（Amazon Linux 2023、AlmaLinux、Rocky Linux）

```bash
# PHP・nginx・Apache関連で、更新できるパッケージがあるかを表示する
# 何も出なければ、まだ修正版が配布されていない
sudo dnf check-update 'php*' 'nginx*' 'httpd*'

# インストール済みのPHP関連パッケージをすべて新しいバージョンにする
# dnf upgrade は入っていないパッケージは新しく入れない
# 'php*' はAmazon Linuxの php8.2-* やRemiの php82-* にも当てはまる
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
# サービス名は0-4で控えたものに合わせる
# apt系：
sudo systemctl restart php8.2-fpm
# dnf系：
sudo systemctl restart php-fpm
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
# サービス名は自分の構成に合わせる（php8.2-fpm / php-fpm / nginx / apache2 / httpd）
systemctl status php8.2-fpm nginx --no-pager
```

### 4-2. バージョンを確認する

```bash
# 更新後のバージョンを表示する。記録表の「更新後のPHP」に書く
php -v
# apt系：
php-fpm8.2 -v
# dnf系：
php-fpm -v
```

### 4-3. 脆弱性が直っているかを確認する

- **ondrej PPA、Remiなど**：4-2のバージョンが、php.netが発表した修正版以上であればよい
- **OS標準のパッケージ（バックポート）**：バージョン番号では判断できません。パッケージの変更履歴にCVE番号が載っているかで確認します

```bash
# パッケージの変更履歴から、目的のCVE番号を探す。1行以上出れば修正が入っている
# apt系：
zcat /usr/share/doc/php8.2-fpm/changelog.Debian.gz | grep CVE-2026-109618
# dnf系：
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
sudo tail -n 50 /var/log/php8.2-fpm.log
# php-fpm（dnf系）：
sudo tail -n 50 /var/log/php-fpm/error.log
```

---

## 5. 切り戻す（失敗したとき）

### 5-1. まず原因を見る

```bash
# サービスが起動しなかった理由をログから表示する（直近50行）
# サービス名は自分の構成に合わせる
sudo journalctl -u php8.2-fpm -n 50 --no-pager
```

よくある原因は、拡張モジュールのバージョンの不一致（一部のパッケージだけが更新された）や、設定ファイルの書式の変更です。足りないパッケージを更新し直すだけで直ることも多いので、すぐに切り戻さずに一度確認します。

### 5-2. パッケージを戻す

1章で保存したバージョンに戻します。**脆弱なバージョンに戻すことになるので、あくまで一時的な対応です。**原因を直したら、改めて更新してください。

```bash
# apt系：バージョンを指定してインストールし直す
# バージョンは1章で保存したファイルから調べる
# PPAなどでは古いバージョンが配布されなくなっていることがあり、その場合は戻せない
sudo apt install php8.2-fpm=<更新前のバージョン> php8.2-common=<更新前のバージョン>

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
| 修正版（php.net） | 8.5.12、8.4.27、8.3.36、8.2.35（2026年10月21日公開） |
| 8.1以前 | 公式の修正は出ない。サポート中のバージョンへの移行、またはOSベンダーのバックポートを確認する |
| 特にリスクが高い構成 | Apache + mod\_php（PHP公式の発表より） |
| 4-3での確認 | `grep CVE-2026-109618`と`grep CVE-2026-109619`の両方が見つかること |

- PHP公式の発表：[PHP: News Archive - 2026](https://www.php.net/archive/2026.php)
- 脆弱性の仕組みと影響：[php2shellのノート](./php2shell-and-nginx-2026-10.md)
