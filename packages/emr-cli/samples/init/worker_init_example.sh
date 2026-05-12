#!/bin/bash

set -euo pipefail

LOG=/tmp/emr_worker_init_example.log
{
  echo "[worker_init_example] host=$(hostname) utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[worker_init_example] ok=1"
} >>"$LOG"

exit 0
