#!/usr/bin/env bash

cd ~/JQuake

JAVA_PID=""
MONITOR_PID=""

BASE_URL="https://api.dmdata.jp/v2"

# DM-D.S.S WebSocket cleanup
function dmdata_cleanup() {
  echo "Checking DM-D.S.S WebSocket."

  response=$(curl -s -f -H "$AUTH_HEADER" "$BASE_URL/socket?status=open")
  if [ $? -ne 0 ]; then
    echo "Failed to check socket."
    return
  fi

  socket_ids=$(echo "$response" | jq -r '.items[].id')

  for id in $socket_ids; do
    curl -s -f -X DELETE -H "$AUTH_HEADER" "$BASE_URL/socket/$id"

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

    response=$(curl -s -f -H "$AUTH_HEADER" "$BASE_URL/socket?status=open")
    if [ $? -ne 0 ]; then
      continue
    fi

    item_count=$(echo "$response" | jq '.items | length')

    if [ "$item_count" -eq 0 ]; then
      if [ -n "$ALERT_EMAIL" ]; then
        echo "Sending alert email."

        BODY="Subject: 【異常】地震監視PC: DM-D.S.S接続異常
DM-D.S.SのWebSocket接続に異常が発生しています。

異常発生時刻: $(date "+%Y-%m-%d %H:%M:%S")
"

        systemd-run --user --no-block bash -c "echo -e \"$BODY\" | msmtp \"$ALERT_EMAIL\"" > /dev/null 2>&1
      fi
      cleanup
    fi
  done
}

# Trap Signal
function cleanup() {
  if [ -n "$MONITOR_PID" ]; then
    kill $MONITOR_PID 2>/dev/null || true
  fi

  if [ -n "$JAVA_PID" ]; then
    kill $JAVA_PID 2>/dev/null || true
  fi

  exit 1
}
trap cleanup SIGINT SIGTERM EXIT

if [ -f .env ]; then
  source .env
fi

if [ -n "$API_KEY" ]; then
  AUTH_HEADER="Authorization: Basic $(echo -n "${API_KEY}:" | base64)"
  dmdata_cleanup
fi

echo "Launching JQuake."

java -Xmx200m -Xms32m -Xmn2m -Djava.net.preferIPv4Stack=true -Dawt.useSystemAAFontSettings=gasp -jar JQuake.jar > /dev/null &
JAVA_PID=$!

if [ -n "$API_KEY" ]; then
  dmdata_monitoring &
  MONITOR_PID=$!
fi

wait $JAVA_PID

