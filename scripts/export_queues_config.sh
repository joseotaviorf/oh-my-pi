#!/bin/bash

function push_to_cloudwatch(){
  # TODO: Implement push to CloudWatch
  echo $1
}

s3Key=$AWS_ACCESS_KEY_ID
s3Secret=$AWS_SECRET_ACCESS_KEY
dbUser=$ASTERISK_DB_USER
dbPwd=$ASTERISK_DB_PASSWORD
file="/var/tmp/results.csv"
fileName="results.csv"

# Check for file errors
rm -rf "${file}"
if [ $? -eq 0 ]; then
  :
else
  push_to_cloudwatch 0
  exit 1
fi

mysql -e "call asterisk.list_queues_agents_uras();" -u ${dbUser} -p${dbPwd}

# Check for DB Errors
if [ $? -eq 0 ]; then
  :
else
  push_to_cloudwatch 0
  exit 1
fi

bucket="bi-etl-ejuice-tmpfiles"
resource="/${bucket}/asterisk/${fileName}"
contentType="text/csv"
dateValue=$(date -R)
stringToSign="PUT\n\n${contentType}\n${dateValue}\n${resource}"
signature=$(echo -en ${stringToSign} | openssl sha1 -hmac ${s3Secret} -binary | base64)

curl -i -X PUT -T "${file}" \
  -H "Host: ${bucket}.s3.amazonaws.com" \
  -H "Date: ${dateValue}" \
  -H "Content-Type: ${contentType}" \
  -H "Authorization: AWS ${s3Key}:${signature}" \
  https://${bucket}.s3.amazonaws.com/asterisk/${fileName}

bucket="5a-datalake"
resource="/${bucket}/raw/asterisk/config/${fileName}"
contentType="text/csv"
dateValue=$(date -R)
stringToSign="PUT\n\n${contentType}\n${dateValue}\n${resource}"
signature=$(echo -en ${stringToSign} | openssl sha1 -hmac ${s3Secret} -binary | base64)

curl -i -X PUT -T "${file}" \
  -H "Host: ${bucket}.s3.amazonaws.com" \
  -H "Date: ${dateValue}" \
  -H "Content-Type: ${contentType}" \
  -H "Authorization: AWS ${s3Key}:${signature}" \
  https://${bucket}.s3.amazonaws.com/raw/asterisk/config/${fileName}


# Check for errors while sending to S3
if [ $? -eq 0 ]; then
  push_to_cloudwatch 1
  exit 0
else
  push_to_cloudwatch 0
  exit 1
fi