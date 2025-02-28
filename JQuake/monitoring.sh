#!/bin/bash

cd ~/JQuake

# Load environment variable
if [ -f .env ]; then
  source .env
fi

if [ -z "$API_KEY" ]; then
  echo "Error: API_KEY is not set. Please set it as an environment variable or in .env file."
  exit 1
fi

if [ -z "$ALERT_EMAIL" ]; then
  echo "Error: ALERT_EMAIL is not set. Please set it as an environment variable or in .env file."
  exit 1
fi

# DM-D.S.S socket check
AUTH_HEADER="Authorization: Basic $(echo -n "${API_KEY}:" | base64)"
BASE_URL="https://api.dmdata.jp/v2"

response=$(curl -s -H "$AUTH_HEADER" "$BASE_URL/socket?status=open")

item_count=$(echo "$response" | jq '.items | length')

if [ "$item_count" -eq 0 ]; then
  echo "No open sockets found. Restarting JQuake..."
  systemctl --user restart jquake

  # Send alert Email
  BODY="Subject: 【異常】地震監視PC: DM-D.S.S接続異常
DM-D.S.SのWebSocket接続に異常が発生しています。
JQuakeサービスを再起動しました。

異常発生時刻: $(date "+%Y-%m-%d %H:%M:%S")
"

  echo -e "$BODY" | msmtp "$ALERT_EMAIL"
fi

