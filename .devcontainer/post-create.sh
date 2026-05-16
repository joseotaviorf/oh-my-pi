#!/usr/bin/env bash
# Re-links pre-built venvs to the bind-mounted workspace (~1–2s). See devcontainer.json for UV_PROJECT_ENVIRONMENT.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -d /home/vscode/.cache ]; then
  sudo chown -R vscode:vscode /home/vscode/.cache 2>/dev/null || true
fi

if [ -n "${GITHUB_TOKEN:-}" ]; then
  git config --global credential.helper "cache --timeout=36000"
  git credential approve <<EOF
protocol=https
host=github.com
username=x-access-token
password=${GITHUB_TOKEN}
EOF
elif ! gh auth status >/dev/null 2>&1; then
  echo "Warning: no GITHUB_TOKEN and gh auth is not configured. Private GitHub fetches may fail. Run: gh auth login"
fi

uv sync --python 3.12

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
