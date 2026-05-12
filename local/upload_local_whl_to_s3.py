import glob
import os

import boto3


s3 = boto3.client("s3")
username = os.getlogin()
s3_bucket = "artifacts.s3.forno.data.quintoandar.com.br"

repo_root = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))

wheels = sorted(
    glob.glob(os.path.join(repo_root, "dist", "bietlejuice_core-*.whl"))
    + glob.glob(os.path.join(repo_root, "dist", "bietlejuice_runtime-*.whl"))
)

if not wheels:
    raise FileNotFoundError(
        "No wheels found in dist/. Run `make build` before uploading."
    )

for local_path in wheels:
    filename = os.path.basename(local_path)
    s3_key = f"bi-etl-ejuice-local/{username}/{filename}"
    print(f"Uploading {filename} to s3://{s3_bucket}/{s3_key}")
    s3.upload_file(
        local_path,
        s3_bucket,
        s3_key,
        ExtraArgs={"ACL": "bucket-owner-full-control"},
    )
    print(f"Uploaded {filename} successfully.")
