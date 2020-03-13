import os
import boto3


s3 = boto3.client('s3')
username = os.getlogin()
s3_bucket = 'artifacts.s3.forno.data.quintoandar.com.br'
s3_folder_path = 'bi-etl-ejuice-local/{username}/bi_etl_ejuice-0.1.0-py3-none-any.whl'.format(username=username)
local_path = '/home/<BIETLEJUICE_FOLDER>/dist/bi_etl_ejuice-0.1.0-py3-none-any.whl'

print("Uploading python wheel to S3")
s3.upload_file(local_path, s3_bucket, s3_folder_path,
               ExtraArgs={'ACL': 'bucket-owner-full-control'})
