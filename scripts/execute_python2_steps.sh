#!/bin/bash

CHANGED_PATHS=$(git diff-tree --no-commit-id --name-only -r HEAD..HEAD~1 | grep 'bietlejuice/db\|bietlejuice/jobs/base\|bietlejuice/jobs/dags\|bietlejuice/jobs/etl\|tests/[A-Za-z_-/]*\.py\|requirements\|setup')
if [ ${#CHANGED_PATHS} -eq 0 ]; then
  echo "===== No changes in Airflow EC2 files! Skipping! ===== "
  exit 0
else
  echo "Changes in Airflow EC2 files detected! Executing step..."
  $1 # command 1
  $2 # command 2
  $3 # command 3
fi
