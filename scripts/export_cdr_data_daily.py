import os
import subprocess
import sys

import boto3
from datetime import datetime, timedelta

args = sys.argv

aws_secret_access_key = os.environ.get('AWS_SECRET_ACCESS_KEY')
aws_access_key_id = os.environ.get('AWS_ACCESS_KEY_ID')
user = os.environ.get('ASTERISK_DB_USER')
password = os.environ.get('ASTERISK_DB_PASSWORD')
psswd = '-p{0}'.format(password)

dt = datetime.today() - timedelta(1)

if len(sys.argv) == 2:
    dt = datetime.strptime(args[1], '%Y-%m-%d')

today = dt.strftime('%Y-%m-%d')
year_month = dt.strftime('%Y-%m')

cdr_path = '/var/tmp/cdr_dump.csv'
filename = 'cdr_dump_{0}.csv'.format(today)

bucket = '5a-datalake'
resource = 'raw/asterisk/cdr/ym={0}/{1}'.format(year_month, filename)

os.remove(cdr_path)

proc = subprocess.Popen(
    ['mysql', '-e', 'call asteriskcdrdb.extract_cdr_data_daily();', '-u', user, psswd],
    stdout=subprocess.PIPE)
proc.communicate()

s3 = boto3.client('s3', aws_access_key_id=aws_access_key_id, aws_secret_access_key=aws_secret_access_key)
s3.put_object(Bucket=bucket, Key=resource, Body=open(cdr_path, 'rb'))
