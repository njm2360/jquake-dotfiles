#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias rwboot='sudo bootctl set-oneshot arch-rw.conf && sudo reboot'
PS1='[\u@\h \W]\$ '
