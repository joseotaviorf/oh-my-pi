#!/bin/bash

if [ -z "$DATABRICKS_TOKEN" ]; then
  echo "Error: DATABRICKS_TOKEN is not set."
  exit 1
fi

CONNECTIONS_FILE="connections.json"

# Process each connection
for row in $(jq -c '.envs[]' "$CONNECTIONS_FILE"); do
  echo "Processing connection: $row"  # Debug statement

  conn_id=$(echo "$row" | jq -r '.conn_id // empty')
  conn_type=$(echo "$row" | jq -r '.conn_type // empty')
  conn_host=$(echo "$row" | jq -r '.host // empty')
  conn_login=$(echo "$row" | jq -r '.login // empty')
  conn_password=$(echo "$row" | jq -r '.password // empty')
  conn_extra=$(echo "$row" | jq -c '.extra // empty' | sed "s/{DATABRICKS_TOKEN}/$DATABRICKS_TOKEN/g")

  echo "Deleting existing connection: $conn_id"  # Debug statement
  astro dev run connections delete "$conn_id"

  echo "Adding new connection: $conn_id"  # Debug statement
  astro dev run connections add "$conn_id" \
    --conn-type "$conn_type" \
    --conn-host "$conn_host" \
    --conn-login "$conn_login" \
    --conn-password "$conn_password" \
    --conn-extra "$conn_extra"
done