import os
import re
import boto3


s3 = boto3.client('s3')
username = os.getlogin()
s3_bucket = 'databricks.s3.forno.data.quintoandar.com.br'
s3_folder_path = 'github-repos/bi-etl-ejuice-local/{username}/spark_jobs'.format(username=username)

composer_dags_folder = 'bietlejuice/dags/'
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
        print(s3_folder_path, dag, file_)
        s3.upload_file(local_path, s3_bucket, remote_path,
                       ExtraArgs={'ACL': 'bucket-owner-full-control'})
        print("File '{}' from dag '{}' successfully uploaded!\n".format(file_, dag))