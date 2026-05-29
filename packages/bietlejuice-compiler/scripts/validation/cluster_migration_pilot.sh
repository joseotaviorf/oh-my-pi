#!/usr/bin/env bash
# Migration-only PR for pilot scopes (validation PR already merged).
# Usage: packages/bietlejuice-compiler/scripts/validation/cluster_migration_pilot.sh <JIRA_KEY> <scope> [--regenerate]
# scope: core | fast_lane | platform
set -euo pipefail

JIRA_KEY="$1"
SCOPE="$2"
REGENERATE=0
if [[ "${3:-}" == "--regenerate" ]]; then
  REGENERATE=1
fi
REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$REPO_ROOT"

VALIDATION_DIR="packages/bietlejuice-compiler/scripts/validation"
TOOLING_BRANCH="DPLT-1255/cluster-migration-tooling"
PROMOTE_SCRIPT="${VALIDATION_DIR}/promote_cluster_validation_to_prod.py"
BRANCH="${JIRA_KEY}/cluster-migration-${SCOPE}"

if [[ "$REGENERATE" -eq 1 ]]; then
  git fetch origin "$TOOLING_BRANCH"
  git checkout -B "$BRANCH" "origin/${TOOLING_BRANCH}"
else
  git checkout master
  git pull origin master
  git checkout -B "$BRANCH"
fi

case "$SCOPE" in
  core)
    uv run --project packages/bietlejuice-compiler python "$PROMOTE_SCRIPT" dags/core/
    ;;
  fast_lane)
    uv run --project packages/bietlejuice-compiler python "$PROMOTE_SCRIPT" dags/ --filter _fast_lane
    ;;
  platform)
    uv run --project packages/bietlejuice-compiler python "$PROMOTE_SCRIPT" dags/platform/
    ;;
  *)
    echo "Unknown scope: $SCOPE" >&2
    exit 1
    ;;
esac

make create-dag-files
while IFS= read -r -d '' path; do
  git add "$path"
done < <(find dags/ \( -name '*_cluster.yml' -o -name '*_declaration.yml' \) -print0)
git commit -m "${JIRA_KEY}: migrate ${SCOPE} DAGs to consolidation cluster presets"
if [[ "$REGENERATE" -eq 1 ]]; then
  git push --force-with-lease origin "$BRANCH"
  echo "Regenerated migration PR for ${SCOPE} on ${BRANCH}"
  exit 0
fi
git push -u origin "$BRANCH"
gh pr create --title "${JIRA_KEY}: migrate ${SCOPE} DAGs to consolidation cluster presets" --body "$(cat <<EOF
## Summary
Promote \`validation.cluster\` to prod \`cluster:\` and remove \`validation:\` for ${SCOPE} shadow DAGs (validation PR already merged).

## Test plan
- [ ] \`make validate-cluster-validation-files\`
- [ ] \`make create-dag-files\`
- [ ] Forno run of representative migrated DAG
EOF
)"
echo "Created migration PR for ${SCOPE} on ${BRANCH}"
