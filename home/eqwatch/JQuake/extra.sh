#!/bin/bash

TARGET_TITLE="更新のお知らせ"
TIMEOUT=60

WAIT_INTERVAL=1
ELAPSED_TIME=0

while [ "$ELAPSED_TIME" -lt "$TIMEOUT" ]; do
  WIN_ID=$(xdotool search --name "$TARGET_TITLE")

  if [ -n "$WIN_ID" ]; then
    for ID in $WIN_ID; do
      xdotool windowfocus --sync "$ID"
      xdotool key "$ID" Alt+F4
      echo "Closed popup. (ID: $ID)"
    done
    exit 0
  fi

  sleep "$WAIT_INTERVAL"
  ELAPSED_TIME=$((ELAPSED_TIME + WAIT_INTERVAL))
done

echo "Popup display timeout."
exit 0

