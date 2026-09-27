#!/bin/bash

[ -f ~/.config/dtv.env ] && source ~/.config/dtv.env

declare -A CHANNEL_MAP=(
  [1]=3270603088
  [2]=3270503080
  [3]=3222433792
  [4]=3270903112
  [5]=3270703096
  [6]=3270803104
  [10]=3223033840
)

if [ -z "$1" ] || [ -z "$EPGSTATION_URL" ]; then
  exit 1
fi

CHANNEL_NO="$1"
CHANNEL_ID="${CHANNEL_MAP[$CHANNEL_NO]}"

if [ -z "$CHANNEL_ID" ]; then
  exit 1
fi

URL="${EPGSTATION_URL}/#/onair/watch?type=m2tsll&channel=${CHANNEL_ID}&mode=0"

firefox "$URL" &
