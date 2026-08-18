#!/usr/bin/env bash
# Run per-dataset evals for all (or listed) dataset stems, then build rollup.
#
# Usage:
#   scripts/run_dataset_queue.sh                  # every datasets/*.yaml stem
#   scripts/run_dataset_queue.sh turnover         # explicit stems only
#   DRY_RUN=1 scripts/run_dataset_queue.sh        # print stems, do not eval
#
# Parallelism (CI-oriented):
#   TARS_EVAL_WORKERS=2              # concurrent per-stem processes (default 2)
#   TARS_EVAL_MAX_CONNECTIONS=<n>    # optional cap on per-stem sample concurrency
# Default per-stem connections = sample count in that dataset (min 1).
# When set, TARS_EVAL_MAX_CONNECTIONS caps that dynamic default.
# Aggregate model connections ≈ WORKERS × (per-stem connections).
# Inspect's max_tasks cannot preserve per-stem log/summary dirs, so the
# queue parallelizes separate run_single_dataset_eval.py processes instead.
#
# Transient-failure tolerance (see src/tars_evals/retry.py):
#   TARS_EVAL_MAX_RETRIES=6          # HTTP retries per model request
#   TARS_EVAL_REQUEST_TIMEOUT=300    # ceiling per request INCLUDING retries
#   TARS_EVAL_RETRY_ON_ERROR=0       # whole-sample retries (expensive)
#
# Writes per-dataset output under logs/per_dataset/<stem>/ and a combined
# batch log at logs/per_dataset/_batch_run.log. Ends with build_rollup.py.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PKG_ROOT"

LOG_BASE="logs/per_dataset"
BATCH_LOG="$LOG_BASE/_batch_run.log"
WORKERS="${TARS_EVAL_WORKERS:-2}"

stems_file="$(mktemp)"
rc_dir="$(mktemp -d)"
trap 'rm -f "$stems_file"; rm -rf "$rc_dir"' EXIT
uv run python scripts/list_dataset_stems.py "$@" >"$stems_file"

if [[ "${DRY_RUN:-}" == "1" ]]; then
    cat "$stems_file"
    stem_count="$(grep -c . "$stems_file" || true)"
    echo "DRY_RUN: would evaluate ${stem_count} dataset(s)" >&2
    exit 0
fi

if ! [[ "$WORKERS" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: TARS_EVAL_WORKERS must be a positive integer (got: ${WORKERS})" >&2
    exit 2
fi

mkdir -p "$LOG_BASE"

# Non-secret config from .env; LiteLLM key from Vault when not already set.
[ -f ./.env ] && { set -a; . ./.env; set +a; } || true
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    KEY="$OPENAI_API_KEY"
elif ! KEY="$(scripts/fetch_litellm_key.sh)"; then
    # Explicit rather than inline command substitution: under `set -e` the
    # inline form aborted the whole queue with no message at all.
    echo "ERROR: could not obtain the LiteLLM key (see above). Nothing was evaluated." >&2
    exit 2
fi
export OPENAI_API_KEY="$KEY" LITELLM_API_KEY="$KEY"

# Drop the previous run's aggregates — but only here, at the point of no
# return, once the stems resolved and the key is in hand. Anything that aborts
# before this (an expired Vault session, an unresolvable stem) leaves the last
# gate result intact, which is exactly the evidence needed to debug the abort.
# Anything that aborts after it must not leave a stale summary that a later
# check_gate.py could mistake for this run's verdict.
rm -f "$LOG_BASE/rollup.json" "gate_summary.json"

failed=0
ran=0
selected_stems=()

# Safe stem token for rc filenames (stems are plain filenames; belt-and-suspenders).
_stem_token() {
    printf '%s' "$1" | tr '/.' '__'
}

_run_one_stem() {
    local stem="$1"
    local stem_log_dir="$LOG_BASE/$stem"
    local token rc
    token="$(_stem_token "$stem")"
    mkdir -p "$stem_log_dir"
    rm -f "$stem_log_dir/summary.json"
    echo "===== $(date -Iseconds) START $stem =====" | tee -a "$BATCH_LOG" "$stem_log_dir/run.log"
    set +e
    uv run python scripts/run_single_dataset_eval.py "$stem" \
        2>&1 | tee -a "$BATCH_LOG" "$stem_log_dir/run.log"
    rc=${PIPESTATUS[0]}
    set -e
    echo "===== $(date -Iseconds) END $stem (exit $rc) =====" | tee -a "$BATCH_LOG" "$stem_log_dir/run.log"
    printf '%s' "$rc" >"$rc_dir/$token"
}

# Bounded process pool (portable: no bash wait -n). Polls until a slot frees.
_pids=()

_reap_finished() {
    local new_pids=() pid
    for pid in "${_pids[@]+"${_pids[@]}"}"; do
        if kill -0 "$pid" 2>/dev/null; then
            new_pids+=("$pid")
        else
            wait "$pid" || true
        fi
    done
    _pids=("${new_pids[@]+"${new_pids[@]}"}")
}

while IFS= read -r stem || [[ -n "$stem" ]]; do
    [[ -z "$stem" ]] && continue
    ran=$((ran + 1))
    selected_stems+=("$stem")

    while ((${#_pids[@]} >= WORKERS)); do
        _reap_finished
        if ((${#_pids[@]} >= WORKERS)); then
            sleep 0.2
        fi
    done

    _run_one_stem "$stem" &
    _pids+=("$!")
done <"$stems_file"

for pid in "${_pids[@]+"${_pids[@]}"}"; do
    wait "$pid" || true
done

if [[ $ran -eq 0 ]]; then
    echo "ERROR: no dataset stems to evaluate" >&2
    exit 1
fi

for stem in "${selected_stems[@]}"; do
    token="$(_stem_token "$stem")"
    if [[ ! -f "$rc_dir/$token" ]]; then
        echo "WARN: $stem missing exit code file (worker crashed?)" >&2
        failed=$((failed + 1))
        continue
    fi
    rc="$(cat "$rc_dir/$token")"
    if [[ "$rc" != "0" ]]; then
        echo "WARN: $stem failed with exit $rc" >&2
        failed=$((failed + 1))
    fi
done

if [[ $failed -gt 0 ]]; then
  echo "ERROR: ${failed}/${ran} per-dataset eval(s) failed" >&2
  exit 1
fi

echo "===== $(date -Iseconds) ROLLUP (${ran} datasets, ${failed} failed) =====" | tee -a "$BATCH_LOG"
set +e
uv run python scripts/build_rollup.py "${selected_stems[@]}" 2>&1 | tee -a "$BATCH_LOG"
rollup_rc=${PIPESTATUS[0]}
set -e

# build_rollup.py is the suite's one authoritative gate (see its fail-closed
# return); propagate it explicitly rather than relying on this being the
# script's last line under `set -o pipefail`.
if [[ $rollup_rc -ne 0 ]]; then
    if [[ $rollup_rc -eq 1 ]]; then
        echo "ERROR: suite gate failed on SQL quality (build_rollup.py exit 1)" >&2
    else
        # exit 2 is "the harness or its infrastructure broke", not a verdict on
        # the SQL: a malformed/missing summary, or a run whose samples mostly
        # errored (LiteLLM outage, VPN drop). Do not read it as a regression.
        echo "ERROR: run did not produce a usable gate result (build_rollup.py exit $rollup_rc)" >&2
    fi
    if [[ -f "gate_summary.json" ]]; then
        # check_gate.py renders the failing/errored samples so CI logs show
        # more than a bare exit code. Its own exit code is redundant here —
        # build_rollup.py already made the authoritative call.
        uv run python scripts/check_gate.py gate_summary.json || true
    fi
    exit "$rollup_rc"
fi
