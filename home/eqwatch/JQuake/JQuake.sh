#!/usr/bin/env bash

cd ~/JQuake

JAVA_PID=""
MONITOR_PID=""

BASE_URL="https://api.dmdata.jp/v2"

# API キーがプロセス一覧に出ないよう stdin から渡す
function dmdata_curl() {
  curl -fsSL --connect-timeout 5 --max-time 10 -K - "$@" <<<"user = \"${API_KEY}:\""
}

# DM-D.S.S WebSocket cleanup
function dmdata_cleanup() {
  echo "Checking DM-D.S.S WebSocket."

  response=$(dmdata_curl "$BASE_URL/socket?status=open")
  if [ $? -ne 0 ]; then
    echo "Failed to check socket."
    return
  fi

  socket_ids=$(echo "$response" | jq -r '.items[].id')

  for id in $socket_ids; do
    dmdata_curl -X DELETE "$BASE_URL/socket/$id"

    if [ $? -ne 0 ]; then
      echo "Failed to close socket ID: $id"
    else
      echo "Closed socket ID: $id"
    fi
  done
}

# Monitoring DM-D.S.S WebSocket
function dmdata_monitoring() {
  local initial_check=true

  while true; do
    if [ "$initial_check" = true ]; then
      sleep 15
      initial_check=false
    else
      sleep 60
    fi

    response=$(dmdata_curl "$BASE_URL/socket?status=open")
    if [ $? -ne 0 ]; then
      continue
    fi

    item_count=$(echo "$response" | jq '.items | length')

    if [ "$item_count" -eq 0 ]; then
      if [ -n "$ALERT_EMAIL" ]; then
        echo "Sending alert email."

        SUBJECT="【異常】地震監視PC: DM-D.S.S接続異常"
        MAIL=$(printf 'To: %s\nSubject: =?UTF-8?B?%s?=\nMIME-Version: 1.0\nContent-Type: text/plain; charset=UTF-8\nContent-Transfer-Encoding: 8bit\n\n%s\n\n異常発生時刻: %s\n' \
          "$ALERT_EMAIL" \
          "$(printf '%s' "$SUBJECT" | base64 -w0)" \
          "DM-D.S.SのWebSocket接続に異常が発生しています。" \
          "$(date "+%Y-%m-%d %H:%M:%S")")

        systemd-run --user --no-block --expand-environment=no \
          --setenv=MAIL_B64="$(printf '%s\n' "$MAIL" | base64 -w0)" \
          --setenv=ALERT_EMAIL="$ALERT_EMAIL" \
          bash -c 'printf "%s" "$MAIL_B64" | base64 -d | msmtp "$ALERT_EMAIL"' > /dev/null 2>&1
      fi
      cleanup
    fi
  done
}

# Trap Signal
function cleanup() {
  echo "Performing cleanup..."

  if [ -n "$MONITOR_PID" ]; then
    echo "Stopping monitoring process (PID: $MONITOR_PID)"
    kill $MONITOR_PID 2>/dev/null || true
    wait $MONITOR_PID 2>/dev/null || true
  fi

  if [ -n "$JAVA_PID" ]; then
    echo "Stopping Java process (PID: $JAVA_PID)"
    kill $JAVA_PID 2>/dev/null || true
    wait $JAVA_PID 2>/dev/null || true
  fi

  exit 1
}

trap cleanup SIGINT SIGTERM

if [ -f ~/.config/jquake.env ]; then
  source ~/.config/jquake.env
fi

if [ -n "$API_KEY" ]; then
  dmdata_cleanup
fi

echo "Launching JQuake."

java -XX:+DisableExplicitGC -XX:+ExitOnOutOfMemoryError -XX:+UseZGC -XX:+AlwaysPreTouch -Xmx2G -Xms2G -Djava.net.preferIPv4Stack=true -Dawt.useSystemAAFontSettings=gasp -jar JQuake.jar > /dev/null &
JAVA_PID=$!

if [ -n "$API_KEY" ]; then
  dmdata_monitoring &
  MONITOR_PID=$!
fi

wait $JAVA_PID
EXIT_CODE=$?

if [ -n "$MONITOR_PID" ]; then
  echo "Stopping monitoring process (PID: $MONITOR_PID)"
  kill $MONITOR_PID 2>/dev/null || true
  wait $MONITOR_PID 2>/dev/null || true
fi

exit $EXIT_CODE

