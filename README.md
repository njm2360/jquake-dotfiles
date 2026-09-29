## 地震監視PC用設定ファイル (記事用)

<https://zenn.dev/njm2360/articles/9c755c5b0fc490>

- `article-2609`: 記事に対応する設定。特定のハードウェアに依存するものは含まない
- `main`: 筆者の実機設定。LUKS、OverlayFS、Zabbix など環境に依存するものを含む

```
packages.txt     インストールするパッケージ
rootfs/          / に配置
home/eqwatch/    ~eqwatch に配置
```

### 置き換えが必要なもの

- `rootfs/boot/loader/entries/arch.conf`: `<ROOT_UUID>`
- `rootfs/etc/systemd/network/20-wired.network`: `<MAC_ADDRESS>`、IP アドレス、ゲートウェイ、DNS
- `rootfs/etc/hostname`, `rootfs/etc/hosts`: ホスト名
- ファイアウォールの `192.168.0.0/24`: LAN のサブネット
- `home/eqwatch/.config/dmdata.env.example`: 拡張子を外し、API キーを記入する(DM-D.S.S を使う場合)

### システム (owner)

```sh
sudo pacman -S --needed - < packages.txt
sudo pacman -S intel-ucode   # AMD の場合は amd-ucode
sudo locale-gen
sudo mkinitcpio -P
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo groupadd -r autologin && sudo gpasswd -a eqwatch autologin
sudo systemctl enable systemd-networkd systemd-resolved systemd-timesyncd systemd-boot-update sshd lightdm ufw fstrim.timer
```

- マイクロコードは mkinitcpio の `microcode` フックが initramfs に組み込むため、ブートエントリに `initrd` 行は不要

### ファイアウォール

SSH は LAN からの接続のみ許可する。ufw のルールは IPv6 にも適用されるため、送信元を指定しないとグローバル IPv6 アドレス宛てに外部から接続できてしまう。

```sh
sudo ufw default deny
sudo ufw allow from 192.168.0.0/24 to any port 22 proto tcp
sudo ufw enable
```

### eqwatch

JQuake 本体は zip を `~/JQuake/` に展開して配置する。

```sh
systemctl --user daemon-reload
systemctl --user enable jquake

# DM-D.S.S を使う場合
chmod 600 ~/.config/dmdata.env
systemctl --user enable jquake-dmdata-check.timer
```

- 同梱の `JQuake.sh` は使わず、`jquake.service` から java を直接起動する。JVM オプションは `jquake.service` で指定する
- 起動前に `dmdata-socket close` で、前回から残っている WebSocket を切断する(JQuake 専用契約の同時接続数は 1)
- `dmdata-socket` はアカウントで開いているすべての WebSocket を対象に切断・計数する。同じアカウントで他のクライアントを併用する場合は、DM-D.S.S 関連の設定を行わない
- `jquake-dmdata-check.timer` が毎分接続数を確認し、接続数 0 の状態が続いた場合に JQuake を再起動する。起動直後は猶予を設け、再起動しても復旧しない場合は猶予を倍に延ばす
- API キーは `~/.config/dmdata.env` から読み込み、curl には標準入力で渡す(`ps` に表示されない)

### カーネルパラメータ

- `sysctl.d/99-local.conf` で、カーネルパニック、OOM、タスクのハング、ロックアップの発生時に自動で再起動する

### Firefox

- `/usr/local/bin/firefox` は Firefox を `firefox.slice`(メモリ上限 2G)の中で起動する。`vm.panic_on_oom=1` のため、上限がないと Firefox がメモリを使い切った際にマシン全体が再起動する
- JQuake からリンクを開くと、パッケージ付属の `firefox.desktop` が `/usr/bin/firefox` を絶対パスで起動する。これを避けるため、`~/.local/share/applications` と `mimeapps.list` で上書きする
