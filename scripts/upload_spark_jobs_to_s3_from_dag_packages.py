import argparse
import os
import re

import boto3

from dags import DAG_PACKAGES_ROOT

parser = argparse.ArgumentParser()
parser.add_argument(dest='s3_bucket')

args = parser.parse_args()

S3 = boto3.client('s3')
S3_FOLDER_PATH = 'github-repos/bi-etl-ejuice/spark_jobs'

LOCAL_SCRIPTS_PATH = os.path.dirname(os.path.realpath(__file__))

def upload_local_file_into_s3(local_path: str, bucket: str, remote_path: str):
    S3.upload_file(local_path, bucket, remote_path,
                       ExtraArgs={'ACL': 'bucket-owner-full-control'})

for root, dirs, files in os.walk(DAG_PACKAGES_ROOT):
    if 'spark_jobs' not in root:
        continue

    dag_name = re.split('/dags/|/|/spark_jobs', root)[-2]

    for file_name in files:
        print(f"Uploading file '{file_name}' from dag '{dag_name}'...")
        spark_job_local_path = f'{root}/{file_name}'
        spark_job_s3_path = f'{S3_FOLDER_PATH}/{dag_name}/{file_name}'
        upload_local_file_into_s3(spark_job_local_path, args.s3_bucket, spark_job_s3_path)
        print(f"File '{file_name}' from dag '{dag_name}' successfully uploaded!\n")


