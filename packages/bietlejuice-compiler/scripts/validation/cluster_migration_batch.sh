#!/usr/bin/env bash
# Batch-run cluster migration stacks for multiple lines.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$REPO_ROOT"

VALIDATION_DIR="packages/bietlejuice-compiler/scripts/validation"
TOOLING_BRANCH="DPLT-1255/cluster-migration-tooling"
STACK_SCRIPT="${VALIDATION_DIR}/cluster_migration_stack.sh"

bootstrap_tooling() {
  if [[ -f "$STACK_SCRIPT" ]]; then
    return 0
  fi
  if git ls-remote --exit-code --heads origin "$TOOLING_BRANCH" &>/dev/null; then
    git fetch origin "$TOOLING_BRANCH"
  else
    echo "Bootstrap branch ${TOOLING_BRANCH} not found on origin" >&2
    exit 1
  fi
  git checkout "origin/${TOOLING_BRANCH}" -- Makefile \
    "${VALIDATION_DIR}/promote_cluster_validation_to_prod.py" \
    "${VALIDATION_DIR}/cluster_migration_pilot.sh" \
    "${VALIDATION_DIR}/cluster_migration_stack.sh" \
    "${VALIDATION_DIR}/cluster_migration_batch.sh" \
    "${VALIDATION_DIR}/bootstrap_cluster_migration_tooling.sh"
  chmod +x "${VALIDATION_DIR}"/cluster_migration_*.sh
}

reset_to_master() {
  if ! git diff --quiet -- "$VALIDATION_DIR" Makefile || ! git diff --cached --quiet -- "$VALIDATION_DIR" Makefile; then
    git stash push -m "cluster migration tooling" -- "$VALIDATION_DIR" Makefile
  fi
  git fetch origin master
  git checkout -B _cluster_migration_base origin/master
  if git stash list | grep -q "cluster migration tooling"; then
    git stash pop
  fi
  bootstrap_tooling
}

bootstrap_tooling

run_stack() {
  local jira="$1"
  local line="$2"
  shift 2
  local validation_branch="${jira}/cluster-validation-${line}"
  if [[ "${REGENERATE:-0}" -eq 0 ]] && git show-ref --verify --quiet "refs/remotes/origin/${validation_branch}"; then
    echo "SKIP ${jira} ${line}: ${validation_branch} already on remote"
    return 0
  fi
  echo "========== ${jira} ${line} $@ =========="
  local regen_flag=()
  if [[ "${REGENERATE:-0}" -eq 1 ]]; then
    regen_flag=(--regenerate)
  fi
  "$STACK_SCRIPT" "$jira" "$line" "${regen_flag[@]}" "$@" || {
    echo "FAILED: ${jira} ${line}" >&2
    return 1
  }
  if [[ "${REGENERATE:-0}" -eq 1 ]]; then
    return 0
  fi
  set +e
  gh stack unstack --local
  unstack_status=$?
  set -e
  if [[ "$unstack_status" -ne 0 ]]; then
    echo "Note: gh stack unstack exited ${unstack_status} (no local stack to tear down)" >&2
  fi
}

run_regenerate_validation_only() {
  local jira="$1"
  local line="$2"
  echo "========== validation-only ${jira} ${line} =========="
  "$STACK_SCRIPT" "$jira" "$line" --regenerate --validation-only || {
    echo "FAILED: ${jira} ${line}" >&2
    return 1
  }
}

run_pilot_regenerate() {
  local jira="$1"
  local scope="$2"
  echo "========== pilot regenerate ${jira} ${scope} =========="
  "${VALIDATION_DIR}/cluster_migration_pilot.sh" "$jira" "$scope" --regenerate || {
    echo "FAILED: pilot ${jira} ${scope}" >&2
    return 1
  }
}

WAVE1=(
  "DPLT-1287 ds_pricing"
  "DPLT-1296 ops_poc"
  "DPLT-1298 planning_and_performance"
  "DPLT-1283 atlas_db"
  "DPLT-1284 broker_xp"
  "DPLT-1300 qube"
)

WAVE2=(
  "DPLT-1285 conversational_xp"
  "DPLT-1286 cross"
  "DPLT-1302 tech_platform"
  "DPLT-1291 governance"
)

WAVE3=(
  "DPLT-1293 house_and_listing --exclude-fast-lane"
  "DPLT-1282 agents --exclude-fast-lane"
  "DPLT-1297 people"
)

WAVE4=(
  "DPLT-1290 for_sale --exclude-fast-lane"
  "DPLT-1295 mlops"
  "DPLT-1299 qcx"
)

WAVE5=(
  "DPLT-1301 support_and_service --exclude-fast-lane"
)

WAVE6=(
  "DPLT-1289 for_rent --exclude-fast-lane"
)

WAVE7=(
  "DPLT-1288 fintech --exclude-fast-lane"
)

WAVE8=(
  "DPLT-1292 growth --exclude-fast-lane"
)

wave="${1:-all}"

run_wave() {
  local name="$1"
  shift
  local entries=("$@")
  echo "===== Starting ${name} (${#entries[@]} lines) ====="
  for entry in "${entries[@]}"; do
    # shellcheck disable=SC2086
    run_stack $entry
    if [[ "${REGENERATE:-0}" -eq 0 ]]; then
      reset_to_master
    fi
  done
}

run_all_waves() {
  run_wave wave1 "${WAVE1[@]}"
  run_wave wave2 "${WAVE2[@]}"
  run_wave wave3 "${WAVE3[@]}"
  run_wave wave4 "${WAVE4[@]}"
  run_wave wave5 "${WAVE5[@]}"
  run_wave wave6 "${WAVE6[@]}"
  run_wave wave7 "${WAVE7[@]}"
  run_wave wave8 "${WAVE8[@]}"
}

run_regenerate_all() {
  export REGENERATE=1
  run_pilot_regenerate DPLT-1255 core
  run_pilot_regenerate DPLT-1256 fast_lane
  run_pilot_regenerate DPLT-1257 platform
  run_all_waves
  run_stack DPLT-1294 journey_optimizer
}

case "$wave" in
  regenerate) run_regenerate_all ;;
  wave1) run_wave wave1 "${WAVE1[@]}" ;;
  wave2) run_wave wave2 "${WAVE2[@]}" ;;
  wave3) run_wave wave3 "${WAVE3[@]}" ;;
  wave4) run_wave wave4 "${WAVE4[@]}" ;;
  wave5) run_wave wave5 "${WAVE5[@]}" ;;
  wave6) run_wave wave6 "${WAVE6[@]}" ;;
  wave7) run_wave wave7 "${WAVE7[@]}" ;;
  wave8) run_wave wave8 "${WAVE8[@]}" ;;
  all)
    run_all_waves
    ;;
  *) echo "Usage: $0 [wave1|wave2|...|all|regenerate]" >&2; exit 1 ;;
esac
