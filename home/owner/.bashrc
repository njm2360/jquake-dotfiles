#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
rwboot() {
    local slot
    slot=$(sed -n 's|.*root=/dev/mapper/arch_cryptroot_\([ab]\) .*|\1|p' /proc/cmdline)
    [ -n "$slot" ] || { echo "rwboot: スロットを判定できませんでした" >&2; return 1; }
    sudo bootctl set-oneshot "arch-$slot-rw.efi" && sudo reboot
}
PS1='[\u@\h \W]\$ '
