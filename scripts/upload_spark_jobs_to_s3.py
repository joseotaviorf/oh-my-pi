import argparse
import os
import re

import boto3

parser = argparse.ArgumentParser()
parser.add_argument(dest='bucket_type')

args = parser.parse_args()

s3 = boto3.client('s3')
s3_bucket = '5a-databricks'
s3_folder_path = f'github-repos/bi-etl-ejuice/spark_jobs/{args.bucket_type}'

composer_dags_folder = 'bietlejuice/jobs/composer/dags/'
abs_path = os.path.dirname(os.path.realpath(__file__))

for root, _, files in os.walk(f'{abs_path}/../{composer_dags_folder}'):
    if 'spark_jobs' not in root:
        continue

    dag = re.split('/dags/|/spark_jobs', root)[1]
    print(f"Processing dag '{dag}'...")

    for file_ in files:
        print(f"Uploading file '{file_}' from dag '{dag}'...")
        s3.upload_file(f'{root}/{file_}', s3_bucket, f'{s3_folder_path}/{dag}/{file_}')
        print(f"File '{file_}' from dag '{dag}' successfully uploaded!\n")
