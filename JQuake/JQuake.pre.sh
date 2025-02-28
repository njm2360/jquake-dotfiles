#!/usr/bin/env bash

cd ~/JQuake

# Load environment variable
if [ -f .env ]; then
  source .env
fi

if [ -z "$API_KEY" ]; then
  echo "Error: API_KEY is not set. Please set it as an environment variable or in .env file."
  exit 1
fi

# DM-D.S.S socket check
echo "Checking DM-D.S.S socket."

AUTH_HEADER="Authorization: Basic $(echo -n "${API_KEY}:" | base64)"
BASE_URL="https://api.dmdata.jp/v2"

response=$(curl -s -H "$AUTH_HEADER" "$BASE_URL/socket?status=open")

socket_ids=$(echo "$response" | jq -r '.items[].id')

for id in $socket_ids; do
  curl -s -X DELETE -H "$AUTH_HEADER" "$BASE_URL/socket/$id"
  echo "Closed socket ID: $id"
done
