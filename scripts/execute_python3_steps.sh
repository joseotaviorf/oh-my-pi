#!/bin/bash

# temporary added until python2->3 full migration
CHANGED_PATHS=$(git diff-tree --no-commit-id --name-only -r HEAD..HEAD~1 | grep 'bietlejuice/jobs/composer\|tests3\|requirements3\|setup3\')
if [ ${#CHANGED_PATHS} -eq 0 ]; then
  echo "===== No changes in Composer files! Skipping! ===== "
  exit 0
else
  echo "Changes in Composer files detected! Executing step..."
  $1 # command 1
  $2 # command 2
  $3 # command 3
fi
