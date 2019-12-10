import argparse
import os
import re

import boto3

parser = argparse.ArgumentParser()
parser.add_argument(dest='s3_bucket')

args = parser.parse_args()

s3 = boto3.client('s3')
s3_folder_path = 'github-repos/bi-etl-ejuice/spark_jobs'

composer_dags_folder = 'bietlejuice/jobs/composer/dags/'
abs_path = os.path.dirname(os.path.realpath(__file__))

for root, _, files in os.walk('{}/../{}'.format(abs_path, composer_dags_folder)):
    if 'spark_jobs' not in root:
        continue

    dag = re.split('/dags/|/spark_jobs', root)[1]
    print("Processing dag '{}'...".format(dag))

    for file_ in files:
        print("Uploading file '{}' from dag '{}'...".format(file_, dag))
        local_path = '{}/{}'.format(root, file_)
        remote_path = '{}/{}/{}'.format(s3_folder_path, dag, file_)
        s3.upload_file(local_path, args.s3_bucket, remote_path,
                       ExtraArgs={'ACL': 'bucket-owner-full-control'})
        print("File '{}' from dag '{}' successfully uploaded!\n".format(file_, dag))
