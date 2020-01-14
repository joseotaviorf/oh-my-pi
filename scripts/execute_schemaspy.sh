#!/bin/bash

TAG_START="<tr class=\"tbl even\" valign=\"top\">"
TAG_END="<td class=\"comment detail\" style=\"display: table-cell;\"></td></tr>"
dbUser=$DB_USER
dbPwd=$DB_PASSWORD

function append_all_schemas() {
  echo "Appending all schemas..."

  DIRLIST=$(ls -d bietlejuice/db/dw/ddl/*)
  unset IFS
  for ITEM in $DIRLIST; do
    IFS='/'
    ELEMENT=($ITEM)
    # append to new index all the schemas in html table format
    echo "$TAG_START" "<td class=\"detail\">
    <a href=\"${ELEMENT[4]}/index.html\">${ELEMENT[4]}</a></td>" "$TAG_END" >>output/index_adjusted.html
    unset IFS
  done

  echo "All schemas appended"
}

CHANGED_PATHS=$(git --no-pager diff --name-only master | grep bietlejuice/db/dw/.*\\.ddl)
if [ -z $CHANGED_PATHS ]; then
  echo "===== No changes in DDL files! Skipping! ===== "
  exit 0
else
  echo "Changes in DDL files detected! Gathering affected schemas..."

  for f in $CHANGED_PATHS; do
    IFS='/'
    ELEMENT=($f)
    CHANGED_SCHEMAS+="${ELEMENT[4]} "
    unset IFS
  done
  ARRAY_SCHEMAS=(${CHANGED_SCHEMAS//:/ })
  ARRAY_SCHEMAS_DIST=($(printf "%s\n" "${ARRAY_SCHEMAS[@]}" | sort -u))
  for s in "${ARRAY_SCHEMAS_DIST[@]}"; do COMMAND_SCHEMAS+=\"$s\",; done
  COMMAND_SCHEMAS=${COMMAND_SCHEMAS::-1}

  echo "===== Updating SchemaSpy... ====="
  java -jar /dependencies/schemaspy-6.1.0.jar \
    -t redshift \
    -dp /dependencies/RedshiftJDBC42-no-awssdk-1.2.36.1060.jar \
    -db dw \
    -host "quintoandar-bi.c6wy0orj1cqf.us-east-1.redshift.amazonaws.com" \
    -port "5439" \
    -schemas $COMMAND_SCHEMAS \
    -u ${dbUser} \
    -p ${dbPwd} \
    -I "(view|pg|vw)_.*" \
    -o ./output

  echo "Uploading documentation to S3..."
  aws s3 cp output/ s3://dbschema.quintoandar.com.br/dw --recursive --acl private
  echo "===== SchemaSpy updated successfully ====="

  echo "===== Updating SchemaSpy index... ===== "
  SKIP_ROWS=0
  INDEX_CONTROL=0

  while IFS="" read -r p || [ -n "$p" ]; do
    # check if it is the start of index items
    if [[ "$p" == *"$TAG_START" && $SKIP_ROWS -eq 0 ]]; then
      # each item contains 4 lines that need to be ignored
      SKIP_ROWS=3
      INDEX_CONTROL=1
    else
      if [[ $SKIP_ROWS -gt 0 ]]; then
        SKIP_ROWS=$((SKIP_ROWS - 1))
      else
        # create and append all schemas as items to index in file
        if [[ $INDEX_CONTROL -eq 1 ]]; then
          append_all_schemas
          INDEX_CONTROL=0
        fi
        echo "$p" >>output/index_adjusted.html
      fi
    fi
  done <output/index.html

  # update file in aws
  aws s3 cp output/index_adjusted.html s3://dbschema.quintoandar.com.br/dw/index.html --acl private
  echo "===== Updated SchemaSpy index... ===== "

fi
