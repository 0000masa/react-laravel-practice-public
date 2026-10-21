# 更新手順書のコマンド解説（OS・systemd・Apache・PHP・パッケージ管理）

Oct 21, 2026 · @masanori

[PHP・Webサーバーのセキュリティ更新手順書](./php-webserver-security-update-runbook.md)に出てくるコマンドが、**何をしているのか**、**なぜそう書くのか**をテーマ別に解説します。手順書の作業中に「このコマンドは何？」と思ったら、下の対応表から該当する章へ飛んでください。

| 手順書の箇所 | 解説の章 |
| --- | --- |
| 0-2 OSを確認する | [1. OSの情報](#1-osの情報etcos-release) |
| 0-3 Webサーバーを確認する | [2. systemdとsystemctl](#2-systemdとsystemctl)、[3. Apacheのコマンド](#3-apacheのコマンドapache2httpdapache2ctl) |
| 0-4 PHPの動かし方を確認する | [3. Apacheのコマンド](#3-apacheのコマンドapache2httpdapache2ctl)、[4. mod\_phpとphp-fpm](#4-mod_phpとphp-fpm)、[2. systemdとsystemctl](#2-systemdとsystemctl) |
| 0-5 PHPのバージョンと入手元 | [5. PHPのコマンドとインストール先](#5-phpのコマンドとインストール先)、[6. パッケージ管理](#6-パッケージ管理の仕組みdpkgaptrpmdnf)、[7. リポジトリ](#7-リポジトリos標準ondrej-pparemi) |
| 1 バックアップ（バージョンの記録） | [9. 作業前のバージョンの記録](#9-作業前のバージョンの記録) |
| 2 パッケージを更新する | [8. 更新のコマンド](#8-更新のコマンド) |
| 3 再起動する | [2. systemdとsystemctl](#2-systemdとsystemctl)、[4. mod\_phpとphp-fpm](#4-mod_phpとphp-fpm) |

---

## 1. OSの情報（/etc/os-release）

### root権限がなくても読めるのか

**読めます。** ファイルの権限を見るとわかります。

```bash
# -L：シンボリックリンクの先にある実体の権限を表示する
ls -lL /etc/os-release
# -rw-r--r-- 1 root root 400 Aug 23  2024 /etc/os-release
```

```
-rw-r--r--
 │  │  │
 │  │  └─ その他のユーザー：r（読める）
 │  └──── グループ：r（読める）
 └─────── 所有者（root）：rw（読み書きできる）
```

その他のユーザーにも`r`（読み取り）が付いているので、一般ユーザーでも`sudo`なしで`cat`できます。書き換えられるのはrootだけです。

なぜ全員が読めるようになっているかというと、**いろいろなプログラムがOSの種類を調べるために読むファイルだから**です。インストーラーやスクリプト、監視エージェントなどは一般ユーザーの権限で動くことが多く、読めないと困ります。中身はOSの名前とバージョンだけで、秘密の情報は入っていません。

なお、Ubuntuなどでは`/etc/os-release`は`/usr/lib/os-release`を指すシンボリックリンク（ショートカットのようなもの）です。どちらを読んでも中身は同じです。

```bash
ls -l /etc/os-release
# lrwxrwxrwx 1 root root 21 Aug 23  2024 /etc/os-release -> ../usr/lib/os-release
```

### OSの情報は大体ここに書いてあるのか

**今のLinuxなら、ほぼ確実にあります。** `/etc/os-release`は、systemdの普及とともに2012年ごろからディストリビューション共通の標準ファイルになりました。手順書で扱うUbuntu、Debian、Amazon Linux 2023、AlmaLinux、Rocky Linuxのすべてにあります。

```bash
cat /etc/os-release
# PRETTY_NAME="Ubuntu 24.04.1 LTS"
# NAME="Ubuntu"
# VERSION_ID="24.04"
# VERSION="24.04.1 LTS (Noble Numbat)"
# VERSION_CODENAME=noble
# ID=ubuntu
# ID_LIKE=debian
# ...
```

| 項目 | 意味 | 上の例 |
| --- | --- | --- |
| `ID` | OSを機械的に判定するための名前 | `ubuntu` |
| `ID_LIKE` | 系統（どのOSの仲間か） | `debian` → apt系とわかる |
| `VERSION_ID` | バージョン | `24.04` |
| `PRETTY_NAME` | 人が読むための表示名 | `Ubuntu 24.04.1 LTS` |

知らないOSに出会っても、`ID_LIKE`を見れば系統がわかります。AlmaLinuxなら`ID_LIKE="rhel centos fedora"`なので、dnf系だと判断できます。

例外と補足です。

- **かなり古いOS**（サポートが終わったCentOS 6など）にはないことがあります。その場合は`/etc/redhat-release`や`/etc/debian_version`を見ます
- **カーネルのバージョンは書かれていません。** カーネルはOSのパッケージとは別に管理されているからです。`uname -r`で確認します
- `hostnamectl`でも同じ情報を見られます。こちらはカーネルのバージョンも一緒に表示されます

---

## 2. systemdとsystemctl

### systemdとは

**systemd**は、Linuxが起動したときに最初に動くプログラム（プロセスID 1番）です。その後、nginxやphp-fpmなどの**常駐するプログラム（サービス）を起動・停止・監視する係**を担います。今のUbuntu、Debian、Amazon Linux、AlmaLinux、Rocky Linuxは、すべてsystemdを使っています。

systemdが管理する対象を**ユニット**と呼びます。サービスはユニットの一種で、`nginx.service`のように`.service`で終わる名前を持ちます。コマンドでは`.service`を省略して`nginx`と書けます。

**systemctl**は、systemdに指示を出したり、状態を問い合わせたりするためのコマンドです。systemd自身のパッケージに含まれていて、OSに最初から入っています。

```bash
# systemctl がどのパッケージに含まれるかを調べる（apt系）
dpkg -S /usr/bin/systemctl
# systemd: /usr/bin/systemctl
```

### systemctl is-active nginx apache2 httpd

**はい、systemdのコマンドです。** 指定した3つのサービスについて、systemdが把握している状態を1行ずつ、指定した順に表示します。

```bash
systemctl is-active nginx apache2 httpd
# active      ← nginx
# inactive    ← apache2
# inactive    ← httpd
```

| 表示 | 意味 |
| --- | --- |
| `active` | 動いている |
| `inactive` | 止まっている、**またはそもそもそのサービスがない** |
| `failed` | 起動しようとして失敗した |

`inactive`は「止まっている」と「存在しない」の区別がつきません。今回の目的（動いているWebサーバーを知る）では、`active`の行を探せば十分なので問題ありません。

3つを並べて書くのは、Apacheのサービス名がOSの系統で違うからです（apt系は`apache2`、dnf系は`httpd`）。どちらのOSでも同じコマンドで済むように、両方を並べています。

状態を見るだけなので、**rootでなくても実行できます**。一方、`restart`のように状態を変えるコマンドには`sudo`が必要です。

### 「どれが動いているか」で判別できるのか

**ほとんどの場合はできます。** ただし、これは「プロセスを直接探す」のではなく、「**systemdが管理しているサービスの状態**を聞く」コマンドだという点に注意が必要です。次の場合は、実際の状態と食い違います。

- systemdを通さずに、手でnginxを起動した場合
- Docker（コンテナ）の中でnginxを動かしている場合

より確実に「実際にリクエストを受けているのはどれか」を知りたいときは、**80番・443番ポートで待ち受けているプロセス**を見ます。

```bash
# 待ち受け中のTCPポートと、そのプロセスを表示する
# -l：待ち受け中のもの、-t：TCP、-n：名前解決せず数字で表示、-p：プロセス名も表示（sudoが必要）
sudo ss -ltnp | grep -E ':(80|443) '
# LISTEN 0 511 0.0.0.0:80 ... users:(("nginx",pid=1234,fd=6),...)
```

### httpdとは何か

**httpdはApache（Apache HTTP Server）のことです。** 名前の由来は「**HTTP D**aemon」です。daemon（デーモン）は、バックグラウンドに常駐して要求を待つプログラムを指すUnixの言葉です。sshd（SSHのデーモン）やcrond（cronのデーモン）と同じ命名です。

同じApacheでも、OSの系統によって名前が違います。

| | apt系（Ubuntu、Debian） | dnf系（Amazon Linux、AlmaLinux、Rocky） |
| --- | --- | --- |
| パッケージ名 | `apache2` | `httpd` |
| サービス名 | `apache2` | `httpd` |
| 本体のコマンド | `/usr/sbin/apache2` | `/usr/sbin/httpd` |
| 制御用のコマンド | `apache2ctl`（`apachectl`も使える） | `apachectl` |
| 設定ファイル | `/etc/apache2/` | `/etc/httpd/` |

Apacheの公式の配布物では、本体の名前は`httpd`です。Debianがパッケージにするときに`apache2`という名前を付け、Ubuntuもそれを引き継いでいます。中身は同じソフトウェアです。nginxはどちらの系統でも`nginx`です。

---

## 3. Apacheのコマンド（apache2・httpd・apache2ctl）

### Linuxに最初から付いているのか

**付いていません。Apacheをインストールしたときに一緒に入るコマンドです。** apt系なら`apache2`パッケージが`/usr/sbin/apache2ctl`を、dnf系なら`httpd`パッケージが`/usr/sbin/httpd`と`/usr/sbin/apachectl`を配置します。Apacheが入っていないサーバーで実行すると、`command not found`になります。

```bash
# そのコマンドがどこにあるかを表示する。何も出なければ入っていない
command -v apache2ctl httpd

# そのファイルがどのパッケージに含まれるかを調べる
# apt系：
dpkg -S /usr/sbin/apache2ctl
# dnf系：
rpm -qf /usr/sbin/httpd
```

`/usr/sbin`の`sbin`は「system binaries」の略で、主に管理者が使うコマンドが置かれる場所です。

### sudo apache2ctl -M と sudo httpd -M の違い

**どちらも「Apacheが読み込んでいるモジュールの一覧を表示する」コマンドで、やっていることは同じです。** 違うのはOSの系統だけです。

- `-M`：設定ファイルを読み込み、有効になっているモジュール（Apacheの機能の部品）を一覧表示します。サーバーを起動したり止めたりはしません
- `sudo`が必要なのは、Apacheの設定ファイルや、そこから参照される証明書などのファイルをroot権限で読む必要があるためです

apt系で`apache2 -M`と直接実行せずに`apache2ctl`を通すのには理由があります。Debian系のApacheは、起動に必要な環境変数（ログの置き場所など）を`/etc/apache2/envvars`に分けて持っています。`apache2ctl`はそれを読み込んでから本体を呼び出してくれます。本体を直接実行すると、その環境変数がなくてエラーになります。dnf系にはこの仕組みがないので、`httpd -M`と直接実行できます。

### | grep -Ei 'php|proxy_fcgi' の意味

`-M`の出力は数十行あるので、PHPに関係する行だけに絞り込みます。

| 部分 | 意味 |
| --- | --- |
| `\|`（パイプ） | 左のコマンドの出力を、右のコマンドの入力に渡す |
| `grep` | 入力から、パターンに一致する行だけを表示する |
| `-E` | 拡張正規表現を使う。`\|`を「または」として扱える |
| `-i` | 大文字・小文字を区別しない |
| `'php\|proxy_fcgi'` | 「phpを含む行」または「proxy\_fcgiを含む行」 |

```
# mod_php の場合の出力例
 php_module (shared)

# php-fpm 経由の場合の出力例
 proxy_fcgi_module (shared)
```

`php_module`が出たら、PHPがApacheの中に組み込まれている（mod\_php）とわかります。`proxy_fcgi_module`は、Apacheがリクエストを外部のFastCGIプロセス（php-fpm）へ転送するためのモジュールです。違いは[4章](#4-mod_phpとphp-fpm)で説明します。

厳密には、`proxy_fcgi_module`が読み込まれているだけで、実際にPHPをそこへ転送しているとは限りません。確実に知りたい場合は、設定ファイルに`SetHandler "proxy:unix:/run/php/php8.2-fpm.sock|fcgi://localhost"`のような転送の設定があるかを確認します。

---

## 4. mod\_phpとphp-fpm

PHPには、PHPを外部から呼び出すための「入口」が複数あります。これを**SAPI**（Server API）と呼びます。手順書に出てくるのは次の3つです。

| SAPI | コマンド／ファイル | 使われ方 |
| --- | --- | --- |
| CLI | `php` | ターミナルからPHPを実行する（`php -v`、`wp`コマンド、cronなど） |
| mod\_php（Apache 2 Handler） | `libphp.so`などのApacheモジュール | Apacheのプロセスの中でPHPを動かす |
| FPM | `php-fpm` | 独立したプロセスとしてPHPを動かす |

### mod\_php：Apacheの中にPHPを組み込む

```
ブラウザ ──> Apache のプロセス
            ┌──────────────────────┐
            │ Apache の処理          │
            │ ＋ PHP（mod_php）      │ ← PHPはApacheの一部として動く
            └──────────────────────┘
```

- PHPがApacheのプロセスに組み込まれています。**PHPを更新したらApacheを再起動**する必要があります
- 画像やCSSを返すだけのApacheのプロセスにも、PHPが載っています。そのぶんメモリを多く使います
- mod\_phpは、Apacheの動かし方（MPM）として`prefork`（1リクエストに1プロセス）でしか使えないのが普通です。同時アクセスに強い`event`が使えません
- 古くからある方式で、設定が簡単なので、昔から動いているサーバーや一部のレンタルサーバーで残っています

### php-fpm：PHPを独立したプロセスで動かす

**FPM**は「FastCGI Process Manager」の略です。PHPを実行するプロセスをいくつか起動しておき、Webサーバーから**FastCGI**という決まった形式でリクエストを受け取って処理します。

```
ブラウザ ──> nginx / Apache ──(FastCGI)──> php-fpm
             静的ファイルは自分で返す       ┌ master プロセス（管理役）
             .php だけを転送する            ├ worker プロセス（PHPを実行）
                                          └ worker プロセス（PHPを実行）
```

- WebサーバーとPHPが別のプロセスなので、**PHPを更新したらphp-fpmだけを再起動**すればよい
- nginxはPHPを組み込む仕組みを持たないので、**nginxでPHPを動かすなら必ずphp-fpm**
- Apacheでも`proxy_fcgi`モジュールを使えばphp-fpmと組み合わせられる。この場合は`event`も使える
- Webサーバーとの通信には、Unixソケット（例：`/run/php/php8.2-fpm.sock`）か、TCPの9000番ポートを使う

### まとめ

| | mod\_php | php-fpm |
| --- | --- | --- |
| PHPが動く場所 | Apacheのプロセスの中 | 独立したphp-fpmのプロセス |
| 組み合わせられるWebサーバー | Apacheのみ | nginx、Apacheなど |
| PHPを更新したときの再起動 | Apache | php-fpm |
| メモリの効率 | 悪い（全プロセスにPHPが載る） | 良い（PHPを動かすプロセスだけ） |
| 今の主流 | 減っている | 主流 |

php2shellでは、PHP公式が「mod\_phpの構成が最もリスクが高い」と発表しています。

---

## 5. PHPのコマンドとインストール先

### php -v や php-fpm -v は、PHPがインストールされたサーバーでしか実行できないのか

**そのとおりです。** `php`や`php-fpm`は、Linuxに最初から付いているコマンドではありません。PHPのパッケージをインストールしたときに配置されるプログラムです。PHPが入っていないサーバーでは`command not found`になります。

さらに、**PHPのパッケージはSAPIごとに分かれています**。そのため、php-fpmは入っているのに`php`コマンド（CLI）は入っていない、ということもありえます。

| apt系のパッケージ | 入るコマンド |
| --- | --- |
| `php8.2-cli` | `php8.2`（と`php`） |
| `php8.2-fpm` | `php-fpm8.2` |
| `libapache2-mod-php8.2` | mod\_php（コマンドではなくApacheのモジュール） |

### どこにインストールされるのか

入手元によって場所が違います。

| 入手元 | CLI | php-fpm | 設定ファイル |
| --- | --- | --- | --- |
| apt系（OS標準、ondrej PPA） | `/usr/bin/php8.2` | `/usr/sbin/php-fpm8.2` | `/etc/php/8.2/cli/php.ini`、`/etc/php/8.2/fpm/php.ini` |
| dnf系（OS標準、Remiのモジュール方式） | `/usr/bin/php` | `/usr/sbin/php-fpm` | `/etc/php.ini`、`/etc/php-fpm.d/www.conf` |
| Remiの並行インストール方式（`php82-*`） | `/opt/remi/php82/root/usr/bin/php`（`php82`でも呼べる） | `/opt/remi/php82/root/usr/sbin/php-fpm` | `/etc/opt/remi/php82/` |
| Dockerの公式イメージ（`php:8.2-fpm`） | `/usr/local/bin/php` | `/usr/local/sbin/php-fpm` | `/usr/local/etc/php/` |

apt系でコマンド名に`8.2`が付くのは、**複数のバージョンを同時に入れられる**ようにするためです。8.1と8.2を両方入れても、`php8.1`と`php8.2`という別の名前になるので衝突しません。`php`という名前は、そのどれか1つを指すリンクです。

```bash
# php が実際にどのファイルを指しているかをたどる
readlink -f "$(command -v php)"
# /usr/bin/php8.2
```

dnf系のOS標準のPHPは、1台に1つのバージョンしか入れない前提なので、コマンド名にバージョンが付きません。

### インストール場所や実行場所で、実行できるかが変わるのか

**「今いるディレクトリ」は関係ありません。関係するのは環境変数`PATH`です。**

シェルは、コマンド名だけを打たれたときに、`PATH`に並んでいるディレクトリを順番に探し、最初に見つかったファイルを実行します。

```bash
# 自分の PATH を表示する（: 区切りで、左から順に探される）
echo "$PATH"
# /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

- `/usr/bin`や`/usr/sbin`は普通`PATH`に入っているので、どのディレクトリにいても`php`や`php-fpm8.2`を実行できます
- Remiの並行インストール方式のように`/opt/...`に入っている場合は、`PATH`に入っていないので、フルパスで実行するか、`php82`のような別名を使います
- `command not found`と出たら、本当に入っていないのか、`PATH`にないだけなのかを次のように確かめます

```bash
# PATH の中から探す。出なければ PATH の中にはない
command -v php-fpm8.2
# よくある場所を直接探す
ls /usr/sbin/php-fpm* /opt/remi/*/root/usr/sbin/php-fpm 2>/dev/null
```

### php -v と php-fpm -v を両方確認する理由

`php`（CLI）と`php-fpm`は**別のバイナリ**です。複数のバージョンが入っているサーバーでは、`php -v`が8.3を示しているのに、Webで実際に動いているphp-fpmは8.2、ということが起こります。Webサイトに効くのはphp-fpmのほうなので、手順書では両方を確認しています。

---

## 6. パッケージ管理の仕組み（dpkg・apt・rpm・dnf）

### パッケージとは

**パッケージ**は、ビルド済みのプログラムと、設定ファイルの雛形、メタデータ（名前、バージョン、どのパッケージに依存するか、インストール時に実行するスクリプト）を1つにまとめたファイルです。形式は系統で2つに分かれます。

| 系統 | パッケージの形式 | 低レベルの道具 | 高レベルの道具 |
| --- | --- | --- | --- |
| Debian系（Ubuntu、Debian） | `.deb` | `dpkg` | `apt`（`apt-cache`、`apt-get`） |
| Red Hat系（Amazon Linux、AlmaLinux、Rocky） | `.rpm` | `rpm` | `dnf` |

### 低レベルの道具と高レベルの道具

| | 低レベル（dpkg／rpm） | 高レベル（apt／dnf） |
| --- | --- | --- |
| 役割 | 手元のパッケージファイルを展開して配置する。**インストール済みの一覧（データベース）**を管理する | リポジトリから**ダウンロード**し、**依存関係を解決**して、低レベルの道具を呼び出す |
| ネットワーク | 使わない | 使う |
| 依存関係 | 足りなければエラーで止まるだけ | 必要なものを自動で一緒に入れる |

普段の作業では高レベルの道具（apt／dnf）を使います。インストール済みのものを調べるだけなら、低レベルの道具（dpkg／rpm）が速くて確実です。

### dpkg -l、apt-cache policy、dnf list installed の違い

| コマンド | 調べる対象 | わかること | わからないこと |
| --- | --- | --- | --- |
| `dpkg -l 'php*'` | インストール済みの一覧（手元のデータベース） | 入っているパッケージとバージョン | どこから入手したか、新しい版があるか |
| `apt-cache policy php8.2-fpm` | apt のカタログ（`apt update`で取得したもの） | 入っているバージョン、入れられる最新のバージョン、**それぞれの入手元のリポジトリ** | ― |
| `dnf list installed 'php*'` | インストール済みの一覧 | 入っているパッケージとバージョン、**入手元のリポジトリ** | ― |

いずれも調べるだけなので、**rootでなくても実行できます**。

#### dpkg -l 'php*' | grep ^ii

```bash
dpkg -l 'php*' | grep ^ii
# ii  php8.2-cli   8.2.35-1+ubuntu22.04.1+deb.sury.org+1  amd64  command-line interpreter ...
# ii  php8.2-fpm   8.2.35-1+ubuntu22.04.1+deb.sury.org+1  amd64  server-side, HTML-embedded ...
```

`dpkg -l`は、過去にアンインストールしたものも含めて表示します。行頭の2文字が状態を表します。

| 行頭 | 意味 |
| --- | --- |
| `ii` | インストールするよう指定されていて（1文字目のi）、実際にインストール済み（2文字目のi） |
| `rc` | 削除済みだが、設定ファイルだけが残っている |
| `un` | 知っているが、入っていない |

`grep ^ii`で「行頭が`ii`の行」、つまり**今インストールされているものだけ**に絞ります。`^`は正規表現で「行頭」を意味します。

#### apt-cache policy php8.2-fpm

```bash
apt-cache policy nginx
# nginx:
#   Installed: (none)                      ← 入っているバージョン
#   Candidate: 1.24.0-2ubuntu7.18          ← apt install で入るバージョン
#   Version table:
#      1.24.0-2ubuntu7.18 500
#         500 http://archive.ubuntu.com/ubuntu noble-updates/main amd64 Packages
#         500 http://security.ubuntu.com/ubuntu noble-security/main amd64 Packages
#      1.24.0-2ubuntu7 500
```

`Version table`には、どのリポジトリからどのバージョンが手に入るかが並びます。インストール済みのバージョンの前には`***`が付きます。手順書でこのコマンドを使うのは、**URLを見て入手元（OS標準かPPAか）を判断するため**です。

#### dnf list installed 'php*'

```bash
dnf list installed 'php*'
# php8.2-cli.x86_64    8.2.35-1.amzn2023.0.1    @amazonlinux
# php8.2-fpm.x86_64    8.2.35-1.amzn2023.0.1    @amazonlinux
```

右端の`@...`が、インストールしたときのリポジトリです。dnfは1つのコマンドで、dpkg -lとapt-cache policyの両方の役割をある程度こなせます。

---

## 7. リポジトリ：OS標準・ondrej PPA・Remi

### 「クラウド上の巨大なレジストリ」という理解は正しいか

**大筋で正しいです。** いくつか補足すると、より正確になります。

- **名前**：Linuxのパッケージの世界では「レジストリ」ではなく**リポジトリ**と呼びます。Dockerのイメージを置く場所はレジストリと呼ぶので、混同しないように注意してください
- **1つの巨大なものではない**：ディストリビューションごと、さらに**OSのバージョンごと**に別のリポジトリがあります。Ubuntu 22.04用と24.04用は別物です。同じものを世界中の多数のサーバー（ミラー）が複製して配っています。EC2では、AWSのリージョン内にあるミラーが使われることが多いです
- **ビルドされたもの**：そのとおりです。ディストリビューションの担当者（メンテナー）が、PHPやnginxの元のソースコードに必要な修正を加え、**そのOSのバージョンに入っているライブラリ（glibc、OpenSSLなど）に合わせてビルド**したものが置かれています
- **署名**：パッケージには、配布元の鍵で署名がされています。apt／dnfは署名を検証してから入れるので、途中で改ざんされたものは入りません

### apt系とdnf系で分かれるのは、そのOSに合わせたビルドを入れるためか

**そのとおりです。** さらに言うと、分かれている理由は2段階あります。

1. **系統の違い**：Debian系とRed Hat系では、パッケージの形式（`.deb`と`.rpm`）、ファイルの配置の流儀、道具（apt／dnf）がまったく違う
2. **同じ系統の中でも、OSのバージョンごとに違う**：Ubuntu 22.04用にビルドしたパッケージは、22.04のライブラリを前提にしている。そのため24.04にはそのまま入れられない

つまり「aptかdnfか」は系統で決まり、「どのパッケージが入るか」はさらにOSのバージョンで決まります。

### OS標準・ondrej PPA・Remiの違い

| | OS標準 | ondrej PPA | Remi |
| --- | --- | --- | --- |
| 作っている人 | ディストリビューション（Canonical、Debian、AWS、AlmaLinuxなど） | Ondřej Surý氏（DebianのPHPパッケージのメンテナー） | Remi Collet氏（PHPやFedoraの開発に関わる人） |
| 対象のOS | そのディストリビューション | Ubuntu（Debian向けは`packages.sury.org`） | Red Hat系（AlmaLinux、Rocky、RHELなど） |
| PHPのバージョン | **OSのバージョンごとに1つが基本**（例：Ubuntu 22.04は8.1、24.04は8.3、Debian 12は8.2） | 複数のバージョンを選べて、並べて入れられる | 複数のバージョンを選べる |
| 修正の届き方 | **バックポート**（バージョンはそのままで修正だけを移植） | php.netの新しいバージョンに追従 | php.netの新しいバージョンに追従 |
| サポートの期間 | OSのサポート期間に合わせる | PHP公式のサポート期間が基本 | PHP公式のサポート期間が基本 |

Amazon Linux 2023は例外的に、OS標準のリポジトリに`php8.1`、`php8.2`のように複数のバージョンが用意されています。

#### バックポートとバージョン番号の読み方

OS標準のパッケージでは、バージョン番号に「元のバージョン」と「ディストリビューションでの修正回数」が並びます。

```
1.24.0 - 2 ubuntu 7.18
│        │        └ Ubuntuでの修正の回数。セキュリティ修正のたびに増える
│        └ Debianでのパッケージの版
└ 元（nginx公式）のバージョン
```

元のバージョンは1.24.0のままでも、Ubuntuが修正を何度も移植しているので、新しい脆弱性が直っていることがあります。手順書の4-3で「バージョン番号ではなく変更履歴のCVE番号で確認する」のはこのためです。

### PPAやRemiは、事前に何か準備が必要か

**必要です。** ただし、新しくインストールする必要があるのは**リポジトリの登録**です。パッケージマネージャー（apt／dnf）自体は、OSに最初から入っています。

登録すると、「このURLからもパッケージを探す」という設定と、そのリポジトリの署名を検証するための鍵がサーバーに追加されます。

```bash
# ondrej PPA を登録する例（Ubuntu）
sudo add-apt-repository ppa:ondrej/php
sudo apt update

# Remi を登録する例（AlmaLinux／Rocky 9）
sudo dnf install epel-release
sudo dnf install https://rpms.remirepo.net/enterprise/remi-release-9.rpm
```

**更新の手順書では、この登録は不要です。** すでにPPAやRemiからPHPを入れているサーバーなら、登録は済んでいて、`apt update`／`dnf`が自動でそこも見に行きます。登録済みのリポジトリは次のコマンドで確認できます。

```bash
# apt系：登録されている外部リポジトリの設定ファイルの一覧
ls /etc/apt/sources.list.d/
# 例：ondrej-ubuntu-php-jammy.sources、github-cli.list など

# dnf系：有効なリポジトリの一覧
dnf repolist
```

外部のリポジトリを登録するということは、**その配布元を信用して、root権限で動くプログラムを入れる**ということです。ondrej PPAやRemiは広く使われていて実績がありますが、よくわからないリポジトリを安易に追加しないでください。

---

## 8. 更新のコマンド

### sudo apt install --only-upgrade 'php8.2-*' の「8.2」は何を指すのか

**「今のバージョンを指定して、それを上げる」という意味ではありません。`8.2`はパッケージの名前の一部です。**

apt系では、PHPのパッケージ名にバージョンの系列が含まれています（`php8.2-fpm`、`php8.2-mysql`など）。`'php8.2-*'`は「名前が`php8.2-`で始まるパッケージすべて」という意味です。つまり「**8.2系のパッケージをすべて**」を指します。

```
'php8.2-*'
 ├─ php8.2-cli
 ├─ php8.2-common
 ├─ php8.2-fpm
 ├─ php8.2-mysql
 └─ ...（名前が php8.2- で始まるもの）
```

そして、それぞれのパッケージを、**同じ名前のまま入れられる最新のバージョン**に上げます。

- 8.2.34 → 8.2.35 のように、**同じ系列の中で**新しくなる
- `php8.3-fpm`は名前が違う別のパッケージなので、**8.3に上がることはない**
- 8.1系を使っているなら`'php8.1-*'`と書く。そうすると、8.1系の中で入れられる最新のもの（OS標準ならバックポートされたもの）に上がる

特定のバージョンを指定したいときは、`php8.2-fpm=8.2.34-1+...`のように`=`でバージョンを付けます。手順書では切り戻し（5-2）で使っています。

### その他の部分

| 部分 | 意味 |
| --- | --- |
| `sudo` | root権限で実行する。パッケージの追加・更新はシステムを書き換えるので必要 |
| `apt install` | 指定したパッケージをインストールする。入っていれば新しいバージョンにする |
| `--only-upgrade` | **入っていないパッケージは新しく入れない**。`php8.2-*`に当てはまるパッケージは何十個もあるので、これがないと不要な拡張モジュールまで全部入ってしまう |
| `'...'`（クォート） | `*`をシェルに展開させず、そのままaptに渡す。クォートがないと、カレントディレクトリに`php8.2-`で始まるファイルがあった場合に、シェルがそのファイル名に置き換えてしまう |

### apt update と apt upgrade の違い

| コマンド | すること |
| --- | --- |
| `apt update` | リポジトリから**カタログ**（どのパッケージのどのバージョンがあるか）を取ってくるだけ。何もインストールしない |
| `apt upgrade` | 入っているパッケージを**すべて**、カタログにある新しいバージョンにする |
| `apt install --only-upgrade <名前>` | 入っているパッケージのうち、**指定したものだけ**を新しいバージョンにする |

`apt update`をせずに`install`すると、古いカタログを見て「もう最新です」と判断してしまいます。そのため、最初に必ず`apt update`をします。dnfは実行するたびに必要に応じてカタログを取り直すので、`update`に当たる手順はありません（`dnf update`は`dnf upgrade`と同じ意味です）。

### dnf upgrade 'php*'

dnf系では、OS標準のPHPのパッケージ名にバージョンが入っていないことが多い（`php-fpm`、`php-cli`など）ので、`'php*'`で「PHP関連すべて」を指定します。どのバージョンの系列が入るかは、パッケージ名ではなく、リポジトリ側の設定（AlmaLinux／Rockyの**モジュールストリーム**など）で決まっています。`dnf upgrade`もaptの`--only-upgrade`と同じく、入っていないパッケージは新しく入れません。

---

## 9. 作業前のバージョンの記録

手順書の1章では、更新前のパッケージのバージョンを画面に表示し、それを作業記録（記録表やチケットなど）にメモします。

```bash
# apt系：インストール済みのPHP・nginx・Apache関連の「名前 バージョン」を表示する
dpkg -l 'php*' 'nginx*' 'apache2*' | grep ^ii | awk '{print $2, $3}'
```

| 部分 | 意味 |
| --- | --- |
| `dpkg -l 'php*' 'nginx*' 'apache2*'` | 名前がそれぞれで始まるパッケージを一覧表示する |
| `grep ^ii` | インストール済みのものだけにする |
| `awk '{print $2, $3}'` | 各行の2列目（名前）と3列目（バージョン）だけを表示する。説明文などの長い列を省いて、メモしやすくする |

```bash
# dnf系：インストール済みのPHP・nginx・Apache関連を「名前-バージョン-リリース」の形で表示する
rpm -qa 'php*' 'nginx*' 'httpd*' | sort
```

| 部分 | 意味 |
| --- | --- |
| `rpm -qa` | インストール済みのパッケージをすべて表示する（`-q`：問い合わせ、`-a`：すべて） |
| `'php*' 'nginx*' 'httpd*'` | 名前がそれぞれで始まるものだけに絞る |
| `sort` | 名前順に並べて読みやすくする |

**ファイルに保存しなくても、画面に出してメモする方式で問題ありません。** 大事なのは「更新前に何が入っていたか」が後で分かることです。ただし、次の点に注意してください。

- **手で書き写さず、出力をそのままコピー＆ペーストする**。バージョン番号は長く、1文字違うと切り戻し（`apt install パッケージ名=バージョン`）で使えません
- **貼り付け先は、サーバーが壊れても見られる場所**（記録表、チケット、社内チャットなど）にする。サーバーの中に保存したファイルは、サーバーごと戻すことになったときに一緒に消えるので、その点ではメモのほうが確実です
