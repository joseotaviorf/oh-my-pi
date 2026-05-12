#!/usr/bin/env bash
# Runs once after the devcontainer is created (postCreateCommand).
#
# The venv at /home/vscode/.venv is pre-built into the container image with all
# third-party wheels already installed. This script re-runs `uv sync` solely to
# re-link the editable workspace packages from the build-time /tmp/workspace/
# paths to the bind-mounted /workspaces/ paths. No wheels are downloaded or
# extracted — it completes in ~1-2 seconds.
#
# UV_PROJECT_ENVIRONMENT=/home/vscode/.venv is set in devcontainer.json
# remoteEnv, so uv targets the correct pre-built venv automatically.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
git config --global --add safe.directory "${REPO_ROOT}"

# devcontainer.json mounts a named volume at /home/vscode/.cache/uv so the uv
# wheel cache persists across container recreations. Docker creates new named
# volumes as root-owned; chown to vscode on first run so uv can write to it.
# `|| true` keeps idempotency: if the cache dir is already vscode-owned (or
# the path doesn't exist because the mount config changed), we don't fail.
if [ -d /home/vscode/.cache/uv ]; then
  sudo chown -R vscode:vscode /home/vscode/.cache/uv 2>/dev/null || true
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

uv sync --python 3.12

# bietlejuice-runtime is a standalone uv project (not a workspace member) and
# its dbr-16-4 env is a sub-project that mirrors Databricks Runtime 16.4's
# Python deps. The image pre-stages both venvs at
# /opt/bietlejuice-runtime-venvs/{root,dbr-16-4}/.venv (outside the bind-mount
# so they survive into the runtime image). Symlink them into the bind-mounted
# workspace tree before `uv sync` so uv sees them as the project venv and only
# re-links the editable bietlejuice-core member (~1-2s, no wheel downloads).
# UV_PROJECT_ENVIRONMENT is unset inside this block so each project resolves
# to its own .venv (otherwise uv would overwrite /home/vscode/.venv).
( unset UV_PROJECT_ENVIRONMENT
  rm -rf packages/bietlejuice-runtime/.venv
  ln -sfn /opt/bietlejuice-runtime-venvs/root/.venv \
          packages/bietlejuice-runtime/.venv
  uv sync --directory packages/bietlejuice-runtime --python 3.12

  rm -rf packages/bietlejuice-runtime/envs/dbr-16-4/.venv
  ln -sfn /opt/bietlejuice-runtime-venvs/dbr-16-4/.venv \
          packages/bietlejuice-runtime/envs/dbr-16-4/.venv
  uv sync --directory packages/bietlejuice-runtime/envs/dbr-16-4 --python 3.12
)

echo "Done — workspace venv at /home/vscode/.venv; runtime venvs at"
echo "        packages/bietlejuice-runtime/.venv and"
echo "        packages/bietlejuice-runtime/envs/dbr-16-4/.venv"
