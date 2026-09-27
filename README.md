## 地震監視PC用設定ファイル

<https://zenn.dev/njm2360/articles/9c755c5b0fc490>

- `article`: 記事執筆時点(記事から行番号リンクあり)
- `main`: 実機の現行設定。記事 + LUKS/Clevis, OverlayFS, nftables, 各種監視

```
packages.txt     pacman -Qqe
rootfs/          / に配置
home/owner/      ~owner に配置
home/eqwatch/    ~eqwatch に配置
```

### 置換が必要なもの

- `rootfs/boot/loader/entries/*.conf`: `<LUKS_PARTITION_UUID>`
- `rootfs/etc/fstab`: `<ESP_UUID>`
- `rootfs/etc/systemd/network/30-vlan200.network`: IP / GW / DNS
- `rootfs/etc/nftables.conf`, `rootfs/etc/zabbix/zabbix_agentd.local.conf`: 監視サーバーのアドレス
- `*.example` → 拡張子を外して配置
  - `/etc/msmtprc`, `/etc/default/health-report`
  - `~/.config/jquake.env`, `~/.config/speaker-check.env`, `~/.config/dtv.env`

パッケージ標準の設定ファイルは触らずドロップインで上書き。`locale.gen`, `nftables.conf` のみ丸ごと。

### システム (owner)

```sh
cp -r home/owner/. ~/
sudo pacman -S --needed - < packages.txt
sudo cp -r rootfs/. /
sudo chmod 600 /etc/default/health-report
sudo chown root:users /etc/msmtprc && sudo chmod 640 /etc/msmtprc
sudo locale-gen
sudo mkinitcpio -P
sudo groupadd -r autologin && sudo gpasswd -a eqwatch autologin
sudo ln -s /etc/apparmor.d/firefox /etc/apparmor.d/disable/firefox
sudo systemctl enable systemd-networkd systemd-resolved systemd-timesyncd systemd-boot-update sshd nftables lightdm apparmor \
  fstrim.timer health-report.timer zabbix-agent prometheus-node-exporter
```

### eqwatch

```sh
cp -r home/eqwatch/. ~/
systemctl --user daemon-reload
systemctl --user enable jquake x0vncserver jihou.timer speaker-check.timer
vncpasswd
```

別途配置: `JQuake.jar`, `JQuake_lib/`, `sounds/`, `~/.local/share/jihou/sound.wav`, `~/.local/share/jihou/boot.wav`

### Secure Boot (sbctl)

UEFI で Setup Mode にしてから

```sh
sudo sbctl create-keys
sudo sbctl enroll-keys -m
sudo sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
sudo sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
sudo sbctl sign -s /boot/vmlinuz-linux-lts
sudo sbctl sign -s -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed /usr/lib/systemd/boot/efi/systemd-bootx64.efi
sudo sbctl verify
```

- `.signed` を登録しないと systemd-boot-update が署名なしの systemd-boot で ESP を上書きする
- Clevis のバインドは Secure Boot 設定後(PCR7 が変わる)

### LUKS / Clevis

```sh
sudo clevis luks bind -d /dev/disk/by-uuid/<LUKS_PARTITION_UUID> tpm2 '{"pcr_bank":"sha256","pcr_ids":"0,2,3,5,6,7"}'
```

自動解除に失敗したらパスフレーズで起動して再バインド

```sh
sudo clevis luks list -d /dev/disk/by-uuid/<LUKS_PARTITION_UUID>
sudo clevis luks unbind -d /dev/disk/by-uuid/<LUKS_PARTITION_UUID> -s 1
sudo clevis luks bind -d /dev/disk/by-uuid/<LUKS_PARTITION_UUID> tpm2 '{"pcr_bank":"sha256","pcr_ids":"0,2,3,5,6,7"}'
```

- PCR確認: `systemd-analyze pcrs`
- カーネル更新で PCR4/9、UEFI設定変更で PCR1 が変わるので除外

### OverlayFS

- 通常起動は上層 tmpfs(1G)、再起動で変更は消える
- 永続化する作業は RW モード(`overlayroot=0`)で
- `pacman -Syu` も RW モードで。`/boot` は overlay の外なのでカーネルだけ更新されモジュールが消える
- HOOKS: overlayroot は filesystems と fsck の間
- タイマーは `Persistent=false`(タイマー状態が再起動で消えるため)

```sh
sudo bootctl set-oneshot arch-rw.conf && sudo reboot   # RW モードで起動
df -h /mnt/rootfs.upper                                # 上層使用量
find /mnt/rootfs.upper/upper -type f | sort            # 上層に書かれたファイル
```

### Firefox

- 同梱の `firefox` プロファイル(unconfined)が同じパスに付くので `disable/` で無効化
- AppArmor の deny はログに出ない。確認は `aa-exec -p firefox-eqwatch -- cat ~/.config/jquake.env`
- `/usr/local/bin/firefox` を通さないと `firefox.slice` に入らず、Firefox の OOM が `vm.panic_on_oom=1` でマシンごと落とす
- パッケージの `firefox.desktop` は絶対パスで起動するので `~/.local/share/applications` で上書き(JQuake のリンク経由)

### その他

- `99-remove-usb.rules`: 内部 USB オーディオ(0573:1573)無効化
- DISPLAY は autostart から `eqwatch-session.target` 経由で渡す(直書きしない)

```sh
sudo reflector --country Japan --age 24 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
```
