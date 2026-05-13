#!/usr/bin/env bash
# Runs once after the devcontainer is created (postCreateCommand).
#
# All three venvs are pre-built into the container image at:
#   /opt/bietlejuice/venvs/workspace   — core + airflow + compiler
#   /opt/bietlejuice/venvs/runtime     — bietlejuice-runtime standalone
#   /opt/bietlejuice/venvs/dbr-16-4   — runtime pinned to DBR 16.4 LTS libs
#
# This script re-runs `uv sync` solely to re-link the editable workspace
# packages from the build-time paths to the bind-mounted /workspaces/ paths.
# No wheels are downloaded or extracted — it completes in ~1-2 seconds.
#
# UV_PROJECT_ENVIRONMENT=/opt/bietlejuice/venvs/workspace is set in
# devcontainer.json remoteEnv, so uv targets the correct pre-built venv.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
git config --global --add safe.directory "${REPO_ROOT}"

# devcontainer.json mounts a named volume at /home/vscode/.cache/uv so the uv
# wheel cache persists across container recreations. Docker creates new named
# volumes as root-owned; chown to vscode on first run so uv can write to it.
# `|| true` keeps idempotency: if the cache dir is already vscode-owned (or
# the path doesn't exist because the mount config changed), we don't fail.
if [ -d /home/vscode/.cache ]; then
  sudo chown -R vscode:vscode /home/vscode/.cache 2>/dev/null || true
fi

# speeds repeated git status / scm refresh by caching directory mtimes for untracked scans
git -C "${REPO_ROOT}" config core.untrackedCache true

# authenticate git non-interactively when GITHUB_TOKEN is available, without
# persisting tokens in git config url rewrites.
if [ -n "${GITHUB_TOKEN:-}" ]; then
  git config --global credential.helper "cache --timeout=36000"
  git credential approve <<EOF
protocol=https
host=github.com
username=x-access-token
password=${GITHUB_TOKEN}
EOF
elif ! gh auth status >/dev/null 2>&1; then
  echo "Warning: no GITHUB_TOKEN and gh auth is not configured."
  echo "Private GitHub fetches may fail. Run: gh auth login"
fi

# Re-link the workspace venv editable packages to the bind-mounted workspace.
# UV_PROJECT_ENVIRONMENT=/opt/bietlejuice/venvs/workspace is inherited from
# devcontainer.json remoteEnv, so uv targets the pre-built venv directly.
uv sync --python 3.12

# Re-link editable packages for the runtime venvs.
# Symlinks from the workspace .venv paths to /opt/bietlejuice/venvs/ keep the
# Makefile's `envs/dbr-16-4/.venv/bin/pytest` path working as expected.
( unset UV_PROJECT_ENVIRONMENT

  rm -rf packages/bietlejuice-runtime/.venv
  ln -sfn /opt/bietlejuice/venvs/runtime \
          packages/bietlejuice-runtime/.venv
  uv sync --directory packages/bietlejuice-runtime --python 3.12

  rm -rf packages/bietlejuice-runtime/envs/dbr-16-4/.venv
  ln -sfn /opt/bietlejuice/venvs/dbr-16-4 \
          packages/bietlejuice-runtime/envs/dbr-16-4/.venv
  uv sync --directory packages/bietlejuice-runtime/envs/dbr-16-4 --python 3.12
)

echo "Done — venvs at /opt/bietlejuice/venvs/{workspace,runtime,dbr-16-4}"
echo "       symlinked into packages/bietlejuice-runtime/{.venv,envs/dbr-16-4/.venv}"
