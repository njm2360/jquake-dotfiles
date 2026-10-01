# jquake-dotfiles

JQuake を常時表示する地震監視 PC の設定ファイルです。Arch Linux 上で、LUKS/Clevis によるディスク暗号化、OverlayFS による読み取り専用ルート、nftables、Zabbix と Graylog による監視を構成しています。

```
packages.txt     インストールするパッケージ (pacman -Qqe の出力)
rootfs/          / に配置
home/owner/      ~owner に配置 (管理ユーザー)
home/eqwatch/    ~eqwatch に配置 (表示用の自動ログインユーザー)
deploy-diff.py   実機との差分表示と配置
zabbix/          Zabbix テンプレート (配置対象外)
```

## 配置

`deploy-diff.py` は、リポジトリのファイルを `.env` の値で置換したうえで実機と比較し、`--apply` を付けると差分のあるファイルを配置します。`.env` は `.env.example` をもとに作成してください。

```sh
uv run deploy-diff.py            # 差分を表示
uv run deploy-diff.py -s         # 差分のあるファイルの一覧だけを表示
uv run deploy-diff.py --apply    # 差分のあるファイルを配置
uv run deploy-diff.py jquake     # パスの一部で対象を絞る
```

ホームディレクトリのファイルはそのまま配置されます。`rootfs/` のファイルは実機の `/tmp` に置かれるので、表示された `apply.sh` を実機で `sudo` で実行してください。未設定のプレースホルダがある場合は配置しません。

### 置換が必要なもの

- `rootfs/etc/kernel/cmdline`, `rootfs/etc/kernel/cmdline-rw`: `<LUKS_PARTITION_UUID>`
- `rootfs/etc/fstab`: `<ESP_UUID>`
- `rootfs/etc/systemd/network/30-vlan200.network`: IP アドレス、ゲートウェイ、DNS
- 監視サーバーのアドレス
  - `rootfs/etc/nftables.conf`
  - `rootfs/etc/zabbix/zabbix_agentd.local.conf`
  - `rootfs/etc/syslog-ng/syslog-ng.conf`
  - `rootfs/usr/local/bin/netconsole-setup`
- `home/eqwatch/.config/JQuake/Settings.properties`: 緯度経度

`*.example` は配置対象外です。値を記入し、拡張子を外した名前で手で配置して、パーミッションを 600 にしてください。

- `home/eqwatch/.config/dmdata.env.example` → `~/.config/dmdata.env` (DM-D.S.S の API キー)
- `home/eqwatch/.config/dtv.env.example` → `~/.config/dtv.env`

パッケージ標準の設定ファイルは書き換えず、ドロップインで上書きしています。例外は `locale.gen` と `nftables.conf` で、これらはファイルごと置き換えます。

## 構築

### システム (owner)

構築は RW モードで行い、最後に OverlayFS へ切り替えます。`mkinitcpio -P` で overlayroot フックが組み込まれると、既定のブートエントリでは再起動で変更が消えます。

```sh
sudo pacman -S --needed - < packages.txt
uv run deploy-diff.py --apply    # 管理 PC で実行し、表示された apply.sh を実機で sudo で実行
sudo locale-gen
sudo mkinitcpio -P
sudo bootctl set-default arch-rw.efi
sudo groupadd -r autologin && sudo gpasswd -a eqwatch autologin
sudo ln -s /etc/apparmor.d/firefox /etc/apparmor.d/disable/firefox
sudo systemctl enable systemd-networkd systemd-resolved systemd-timesyncd systemd-boot-update sshd nftables lightdm apparmor syslog-ng@default netconsole \
  fstrim.timer eqwatch-status.timer smart-selftest.timer zabbix-agent boot-ro
sudo systemctl disable systemd-network-generator
sudo systemctl mask archlinux-keyring-wkd-sync.timer systemd-tpm2-setup-early.service systemd-pcrproduct.service systemd-pcrlogin@.service
sudo systemctl --global disable p11-kit-server.socket
```

構築が終わったら `sudo bootctl set-default arch.efi` で OverlayFS に切り替えます。

### eqwatch

```sh
systemctl --user daemon-reload
systemctl --user enable jquake x0vncserver jihou.timer jquake-dmdata-check.timer
vncpasswd
```

次のファイルはリポジトリに含まれないので、別途配置してください。

- `~/JQuake/` に `JQuake.jar`, `JQuake_lib/`, `sounds/`
- `~/.local/share/jihou/` に `sound.wav`, `boot.wav`

### Secure Boot (sbctl)

UEFI の設定で Setup Mode にしてから実行します。

```sh
sudo sbctl create-keys
sudo sbctl enroll-keys -m
sudo sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
sudo sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
sudo sbctl sign -s /boot/vmlinuz-linux-lts
sudo sbctl sign -s -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed /usr/lib/systemd/boot/efi/systemd-bootx64.efi
sudo sbctl verify
```

- 最後の `.signed` を登録しないと、systemd-boot-update が署名のない systemd-boot で ESP を上書きします。
- UKI (`/boot/EFI/Linux/*.efi`) は、mkinitcpio が生成するたびに sbctl の post フックが署名します。
- Secure Boot を設定すると PCR7 が変わるので、Clevis のバインドはその後に行います。

### LUKS / Clevis

```sh
sudo clevis luks bind -d /dev/disk/by-uuid/<LUKS_PARTITION_UUID> tpm2 '{"pcr_bank":"sha256","pcr_ids":"0,2,3,5,6,7"}'
```

TPM による自動解除に失敗した場合は、パスフレーズで起動してバインドし直します。

```sh
sudo clevis luks list -d /dev/disk/by-uuid/<LUKS_PARTITION_UUID>
sudo clevis luks unbind -d /dev/disk/by-uuid/<LUKS_PARTITION_UUID> -s <SLOT>   # list で確認したスロット番号
sudo clevis luks bind -d /dev/disk/by-uuid/<LUKS_PARTITION_UUID> tpm2 '{"pcr_bank":"sha256","pcr_ids":"0,2,3,5,6,7"}'
```

- PCR の値は `systemd-analyze pcrs` で確認できます。
- PCR4/9/11 は UKI の更新や RW モードとの切り替えで、PCR1 は UEFI の設定変更で変わるため、バインド対象から外しています。
- `loader.conf` は systemd-boot が PCR5 に測定します。変更した場合は、コメントだけの変更でもバインドし直してください。既定のエントリは `loader.conf` ではなく `bootctl set-default` (EFI 変数) で切り替えます。
- UKI で起動すると、systemd は TPM の NvPCR を扱うユニットを実行します。この構成では `systemd-tpm2-setup-early`、`systemd-pcrproduct`、`systemd-pcrlogin@` が NvPCR を扱えずに失敗し (`No such file or directory`)、failed ユニットとして Zabbix に通知されるため、マスクしています。

## 運用メモ

### OverlayFS

- 通常の起動では上層が tmpfs (1G) になり、変更は再起動で消えます。
- 変更を残す作業は RW モード (`overlayroot=0`) で行います。
- カーネルは UKI として起動します。mkinitcpio の preset で、通常の起動用の `arch.efi` を `/etc/kernel/cmdline` から、RW モード用の `arch-rw.efi` を `/etc/kernel/cmdline-rw` から生成します。Secure Boot が有効な場合、UKI に埋め込んだ cmdline はブートエントリから上書きできないため、cmdline ごとに UKI を分けています。cmdline を変更した場合は、`mkinitcpio -P` で UKI を生成し直してください。
- `pacman -Syu` も RW モードで行います。`/boot` は overlay の外にあるため、通常の起動で更新するとカーネルだけが新しくなり、再起動後に対応するモジュールがなくなります。
- OverlayFS で起動しているときは、`boot-ro.service` が `/boot` を読み取り専用にします。カーネルパニックで ESP が dirty になるのを防ぐためです。
- mkinitcpio の HOOKS では、overlayroot を filesystems と fsck の間に置いています。
- タイマーの状態は再起動で消えるので、タイマーは `Persistent=false` にしています。

```sh
sudo bootctl set-oneshot arch-rw.efi && sudo reboot    # 次回だけ RW モードで起動
df -h /mnt/rootfs.upper                                # 上層の使用量
find /mnt/rootfs.upper/upper -type f | sort            # 上層に書き込まれたファイル
```

### Firefox

- AppArmor パッケージに含まれる `firefox` プロファイル (unconfined) が同じ実行ファイルに適用されるため、`disable/` で無効化して `firefox-eqwatch` を使っています。
- AppArmor で拒否されたアクセスはログに出ません。拒否されることは `aa-exec -p firefox-eqwatch -- cat ~/.config/dmdata.env` で確認できます。
- Firefox は `/usr/local/bin/firefox` 経由で起動し、メモリ上限のある `firefox.slice` に入れています。`vm.panic_on_oom=1` なので、上限がないと Firefox のメモリ不足でマシン全体が再起動します。
- パッケージの `firefox.desktop` は `/usr/bin/firefox` を絶対パスで起動するので、`~/.local/share/applications` で上書きしています (JQuake からリンクを開く場合)。

### Graylog

- netconsole のログは送信元が IP アドレスになるので、Graylog のストリームルールは `source` のホスト名と IP アドレスの両方で拾います。
- netconsole はコンソールの loglevel に従います。ERR 以上を送るため、`sysctl.d` で `kernel.printk` を上書きしています。

### Zabbix

- `zabbix/eqwatch.yaml` をインポートし、`Linux by Zabbix agent` と一緒にホストへリンクします。
- 通知は Zabbix サーバーのメディアタイプで設定します。
- しきい値はマクロ `{$EQWATCH.*}` で、音声の出力先などは `/etc/default/eqwatch-status` で設定します。
- 現在の値は `sudo eqwatch-status` で確認できます。

### その他

- `99-remove-usb.rules` で内部の USB オーディオデバイス (0573:1573) を無効化しています。
- `DISPLAY` はユニットに直接書かず、Openbox の autostart から `eqwatch-session.target` 経由で渡しています。
- ミラーリストの更新:

```sh
sudo reflector --country Japan --age 24 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
```
