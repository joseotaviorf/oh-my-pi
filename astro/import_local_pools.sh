#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f local_pools.json ]; then
  echo "Error: local_pools.json not found."
  exit 1
fi

echo "Importing Airflow pools from local_pools.json"

jq -c '.pools[]' "local_pools.json" | while IFS= read -r row; do
  pool_name=$(echo "$row" | jq -r '.pool_name')
  slots=$(echo "$row" | jq -r '.slots')
  description=$(echo "$row" | jq -r '.description // empty')

  echo "  Setting pool: ${pool_name} (${slots} slots)"
  astro dev run pools set "$pool_name" "$slots" "$description" < /dev/null
done

echo "Airflow pools import completed."
