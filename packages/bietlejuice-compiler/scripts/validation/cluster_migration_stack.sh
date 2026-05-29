#!/usr/bin/env bash
# Create gh-stack PR pair for cluster validation migration of a dags/ line.
# Usage: packages/bietlejuice-compiler/scripts/validation/cluster_migration_stack.sh <JIRA_KEY> <line> [--exclude-fast-lane] [--migration-only] [--regenerate] [--validation-only]
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <JIRA_KEY> <line> [--exclude-fast-lane] [--migration-only] [--regenerate] [--validation-only]" >&2
  exit 1
fi

JIRA_KEY="$1"
LINE="$2"
EXCLUDE_FAST_LANE=0
MIGRATION_ONLY=0
REGENERATE=0
VALIDATION_ONLY=0
shift 2
for arg in "$@"; do
  case "$arg" in
    --exclude-fast-lane) EXCLUDE_FAST_LANE=1 ;;
    --migration-only) MIGRATION_ONLY=1 ;;
    --regenerate) REGENERATE=1 ;;
    --validation-only) VALIDATION_ONLY=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$REPO_ROOT"

VALIDATION_DIR="packages/bietlejuice-compiler/scripts/validation"
TOOLING_BRANCH="DPLT-1255/cluster-migration-tooling"
PROMOTE_SCRIPT="${VALIDATION_DIR}/promote_cluster_validation_to_prod.py"

git config rerere.enabled true
git config remote.pushDefault origin

VALIDATION_SUFFIX="cluster-validation-${LINE}"
MIGRATION_SUFFIX="cluster-migration-${LINE}"
VALIDATION_BRANCH="${JIRA_KEY}/${VALIDATION_SUFFIX}"
MIGRATION_BRANCH="${JIRA_KEY}/${MIGRATION_SUFFIX}"
DAG_PATH="dags/${LINE}/"

run_extract() {
  local path="$1"
  make extract-cluster-validation-files "DAG_PATH=${path}" STRIP_DECLARATION=1
}

extract_line() {
  if [[ "$EXCLUDE_FAST_LANE" -eq 1 ]]; then
    local found=0
    while IFS= read -r -d '' decl; do
      local dag_dir
      dag_dir="$(dirname "$decl")"
      if [[ "$dag_dir" == *"_fast_lane" ]]; then
        continue
      fi
      found=1
      run_extract "${dag_dir}/"
    done < <(find "$DAG_PATH" -name '*_declaration.yml' -print0)
    if [[ "$found" -eq 0 ]]; then
      echo "No declarations found under ${DAG_PATH}" >&2
      exit 1
    fi
  else
    run_extract "$DAG_PATH"
  fi
}

stage_line_changes() {
  while IFS= read -r -d '' path; do
    git add "$path"
  done < <(find dags/ \( -name '*_cluster.yml' -o -name '*_declaration.yml' \) -print0)
  if [[ -f dags/dependencies.yaml ]] && ! git diff --quiet dags/dependencies.yaml; then
    git add dags/dependencies.yaml
  fi
}

promote_line() {
  local extra_args=()
  if [[ "$EXCLUDE_FAST_LANE" -eq 1 ]]; then
    extra_args+=(--exclude _fast_lane)
  fi
  uv run --project packages/bietlejuice-compiler python "$PROMOTE_SCRIPT" "$DAG_PATH" ${extra_args[@]+"${extra_args[@]}"}
}

stash_tooling_if_dirty() {
  if ! git diff --quiet -- "$VALIDATION_DIR" Makefile || ! git diff --cached --quiet -- "$VALIDATION_DIR" Makefile; then
    git stash push -m "cluster migration tooling" -- "$VALIDATION_DIR" Makefile
  fi
}

pop_tooling_stash() {
  if git stash list | grep -q "cluster migration tooling"; then
    git stash pop
    chmod +x "${VALIDATION_DIR}"/cluster_migration_*.sh
  fi
}

checkout_migration_base() {
  git fetch origin master
  git checkout -B _cluster_migration_base origin/master
}

regenerate_validation() {
  git fetch origin "$TOOLING_BRANCH"
  git checkout -B "$VALIDATION_BRANCH" "origin/${TOOLING_BRANCH}"
  extract_line
  make create-dag-files
  stage_line_changes
  if git diff --cached --quiet; then
    echo "No validation changes for ${LINE}" >&2
    exit 1
  fi
  git commit -m "${JIRA_KEY}: extract cluster validation files for ${LINE}"
  git push --force-with-lease origin "$VALIDATION_BRANCH"
}

regenerate_migration() {
  if ! git ls-remote --exit-code --heads origin "$MIGRATION_BRANCH" &>/dev/null; then
    echo "No remote migration branch ${MIGRATION_BRANCH}; skipping migration regenerate"
    return 0
  fi
  git fetch origin "$VALIDATION_BRANCH"
  git checkout -B "$MIGRATION_BRANCH" "origin/${VALIDATION_BRANCH}"
  promote_line
  make create-dag-files
  stage_line_changes
  if git diff --cached --quiet; then
    echo "No migration changes for ${LINE} (already on consolidation presets)"
    return 0
  fi
  git commit -m "${JIRA_KEY}: migrate ${LINE} DAGs to consolidation cluster presets"
  git push --force-with-lease origin "$MIGRATION_BRANCH"
}

if [[ "$REGENERATE" -eq 1 ]]; then
  if [[ "$MIGRATION_ONLY" -eq 1 ]]; then
    git fetch origin "$TOOLING_BRANCH"
    git checkout -B "$MIGRATION_BRANCH" "origin/${TOOLING_BRANCH}"
    promote_line
    make create-dag-files
    stage_line_changes
    if git diff --cached --quiet; then
      echo "No migration changes for ${LINE}" >&2
      exit 1
    fi
    git commit -m "${JIRA_KEY}: migrate ${LINE} DAGs to consolidation cluster presets"
    git push --force-with-lease origin "$MIGRATION_BRANCH"
    echo "Regenerated migration-only ${MIGRATION_BRANCH}"
    exit 0
  fi
  regenerate_validation
  if [[ "$VALIDATION_ONLY" -eq 0 ]]; then
    regenerate_migration
    echo "Regenerated stack for ${LINE}: ${VALIDATION_BRANCH} -> ${MIGRATION_BRANCH}"
  else
    echo "Regenerated validation-only ${VALIDATION_BRANCH}"
  fi
  exit 0
fi

stash_tooling_if_dirty
checkout_migration_base
pop_tooling_stash

if [[ ! -f "$PROMOTE_SCRIPT" ]]; then
  if git ls-remote --exit-code --heads origin "$TOOLING_BRANCH" &>/dev/null; then
    git fetch origin "$TOOLING_BRANCH"
  else
    echo "Bootstrap tooling missing; ensure ${TOOLING_BRANCH} is pushed" >&2
    exit 1
  fi
  git checkout "origin/${TOOLING_BRANCH}" -- Makefile \
    "${VALIDATION_DIR}/promote_cluster_validation_to_prod.py" \
    "${VALIDATION_DIR}/cluster_migration_pilot.sh" \
    "${VALIDATION_DIR}/cluster_migration_stack.sh" \
    "${VALIDATION_DIR}/cluster_migration_batch.sh" \
    "${VALIDATION_DIR}/bootstrap_cluster_migration_tooling.sh" || {
    echo "Bootstrap tooling missing; ensure ${TOOLING_BRANCH} is pushed" >&2
    exit 1
  }
fi

if [[ "$MIGRATION_ONLY" -eq 1 ]]; then
  git checkout -b "$MIGRATION_BRANCH"
  promote_line
  make create-dag-files
  stage_line_changes
  git commit -m "${JIRA_KEY}: migrate ${LINE} DAGs to consolidation cluster presets"
  git push -u origin "$MIGRATION_BRANCH"
  gh pr create --title "${JIRA_KEY}: migrate ${LINE} DAGs to consolidation cluster presets" --body "$(cat <<EOF
## Summary
Promote \`validation.cluster\` to prod \`cluster:\` and remove \`validation:\` blocks for ${LINE} shadow DAGs.

## Test plan
- [ ] \`make validate-cluster-validation-files\`
- [ ] \`make create-dag-files\`
- [ ] Forno run of representative migrated DAG
EOF
)"
  echo "Created migration-only PR for ${LINE} on ${MIGRATION_BRANCH}"
  exit 0
fi

gh stack init -p "${JIRA_KEY}" "${VALIDATION_SUFFIX}"
extract_line
make create-dag-files
stage_line_changes
git commit -m "${JIRA_KEY}: extract cluster validation files for ${LINE}"

gh stack add "${MIGRATION_SUFFIX}"
promote_line
make create-dag-files
stage_line_changes
if git diff --cached --quiet; then
  echo "No migration changes for ${LINE} (already on consolidation presets); skipping migration commit"
else
  git commit -m "${JIRA_KEY}: migrate ${LINE} DAGs to consolidation cluster presets"
fi

set +e
gh stack submit --auto --remote origin --open
submit_status=$?
set -e
if [[ "$submit_status" -ne 0 && "$submit_status" -ne 9 ]]; then
  exit "$submit_status"
fi

ensure_remote_prs() {
  if ! git show-ref --verify --quiet "refs/remotes/origin/${VALIDATION_BRANCH}"; then
    git push -u origin "$VALIDATION_BRANCH"
  fi
  if ! git show-ref --verify --quiet "refs/remotes/origin/${MIGRATION_BRANCH}"; then
    git push -u origin "$MIGRATION_BRANCH"
  fi
  if [[ "$(gh pr list --head "$VALIDATION_BRANCH" --json number --jq 'length')" -eq 0 ]]; then
    gh pr create --head "$VALIDATION_BRANCH" --base master \
      --title "${JIRA_KEY}: extract cluster validation files for ${LINE}" \
      --body "$(cat <<EOF
## Summary
Extract \`*_cluster.yml\` validation files for ${LINE} DAGs (cluster validation migration).

## Test plan
- [ ] \`make validate-cluster-validation-files\`
- [ ] \`make create-dag-files\`
EOF
)"
  fi
  if [[ "$(gh pr list --head "$MIGRATION_BRANCH" --json number --jq 'length')" -eq 0 ]]; then
    gh pr create --head "$MIGRATION_BRANCH" --base "$VALIDATION_BRANCH" \
      --title "${JIRA_KEY}: migrate ${LINE} DAGs to consolidation cluster presets" \
      --body "$(cat <<EOF
## Summary
Promote \`validation.cluster\` to prod \`cluster:\` and remove \`validation:\` blocks for ${LINE} shadow DAGs.

## Test plan
- [ ] \`make validate-cluster-validation-files\`
- [ ] \`make create-dag-files\`
- [ ] Forno run of representative migrated DAG
EOF
)"
  fi
}

ensure_remote_prs
echo "Submitted stack for ${LINE}: ${VALIDATION_BRANCH} -> ${MIGRATION_BRANCH}"
