#!/bin/bash

CHANGED_PATHS=$(git diff-tree --no-commit-id --name-only -r HEAD..HEAD~1 | grep 'bietlejuice/db\|bietlejuice/jobs/base\|bietlejuice/jobs/dags\|bietlejuice/jobs/etl\|tests/[A-Za-z_-/]*\.py\|requirements\|setup')
if [ ${#CHANGED_PATHS} -eq 0 ]; then
  echo "===== No changes in Airflow EC2 files! Skipping! ===== "
  exit 0
else
  echo "Changes in Airflow EC2 files detected! Executing step..."
  echo "### Executing command 1"
  $1

  if [ -n "$2" ]; then
    echo "### Executing command 2"
    $2 || exit 1
  fi

  if [ -n "$3" ]; then
    echo "### Executing command 3"
    $3 || exit 1
  fi
fi
