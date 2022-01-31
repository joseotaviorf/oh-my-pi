#!/bin/bash

# temporary added until python2->3 full migration
CHANGED_PATHS=$(git diff-tree --no-commit-id --name-only -r HEAD..HEAD~1 | grep 'bietlejuice/jobs/composer\|tests3\|requirements3\|setup3')
if [ ${#CHANGED_PATHS} -eq 0 ]; then
  echo "===== No changes in Composer files! Skipping! ===== "
  exit 0
else
  echo "Changes in Composer files detected! Executing step..."
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
