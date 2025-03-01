#!/usr/bin/env bash

cd ~/JQuake

JAVA_PID=""
MONITOR_PID=""

# Load environment variables
if [ -f .env ]; then
  source .env
fi

if [ -n "$API_KEY" ]; then
  # DM-D.S.S websocket check
  echo "Checking DM-D.S.S WebSocket."

  AUTH_HEADER="Authorization: Basic $(echo -n "${API_KEY}:" | base64)"
  BASE_URL="https://api.dmdata.jp/v2"

  response=$(curl -s -f -H "$AUTH_HEADER" "$BASE_URL/socket?status=open")

  socket_ids=$(echo "$response" | jq -r '.items[].id')

  for id in $socket_ids; do
    curl -s -f -X DELETE -H "$AUTH_HEADER" "$BASE_URL/socket/$id"

    if [ $? -ne 0 ]; then
      echo "Warning: Failed to close socket ID: $id"
    else
      echo "Closed socket ID: $id"
    fi
  done
fi

# Launch JQuake
echo "Launching JQuake."

java -Xmx200m -Xms32m -Xmn2m -Djava.net.preferIPv4Stack=true -Dawt.useSystemAAFontSettings=gasp -jar JQuake.jar > /dev/null &
JAVA_PID=$!

# Trap Signal
cleanup() {
  if [ -n "$MONITOR_PID" ]; then
    kill $MONITOR_PID 2>/dev/null || true
  fi

  if [ -n "$JAVA_PID" ]; then
    kill $JAVA_PID 2>/dev/null || true
  fi

  exit 1
}
trap cleanup SIGINT SIGTERM EXIT

# Monitoring DM-D.S.S WebSocket
monitor_websocket() {
  initial_check=true

  while true; do
    if [ "$initial_check" = true ]; then
      sleep 15
      initial_check=false
    else
      sleep 60
    fi

    response=$(curl -s -f -H "Authorization: Basic $(echo -n "${API_KEY}:" | base64)" "https://api.dmdata.jp/v2/socket?status=open")
    if [ $? -ne 0 ]; then
      continue
    fi

    item_count=$(echo "$response" | jq '.items | length')

    if [ "$item_count" -eq 0 ]; then
      # Send alert email
      if [ -n "$ALERT_EMAIL" ]; then
        echo "Sending alert email."

        BODY="Subject: 【異常】地震監視PC: DM-D.S.S接続異常
DM-D.S.SのWebSocket接続に異常が発生しています。

異常発生時刻: $(date "+%Y-%m-%d %H:%M:%S")
"

	systemd-run --user --no-block bash -c "echo -e \"$BODY\" | msmtp \"$ALERT_EMAIL\" > /dev/null 2>&1"
      fi

      kill $JAVA_PID
      exit 1
    fi
  done
}


if [ -n "$API_KEY" ]; then
  monitor_websocket &
  MONITOR_PID=$!
fi

wait $JAVA_PID

