#!/usr/bin/env bash
# Lists unique DAG folder names (dags/<domain>/<dag_name>/...) touched between HEAD~1 and HEAD.
# Used by create-dag-files-from-git-diff and release upload helpers.
set -euo pipefail

git diff --name-only HEAD~1 HEAD | awk '
  /^dags\// {
    n = split($0, p, "/")
    if (n >= 3) print p[3]
  }
' | sort -u
