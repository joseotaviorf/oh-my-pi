import argparse
import logging
import os
import re
import sys
import tempfile
import zipfile
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import partial
from os import path

import boto3
from botocore.config import Config
from tqdm import tqdm

_COMPILER_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
BI_ETL_EJUICE_ROOT = os.path.dirname(os.path.dirname(_COMPILER_ROOT))
for _p in (BI_ETL_EJUICE_ROOT, _COMPILER_ROOT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from dags import DAG_PACKAGES_ROOT

boto3.set_stream_logger(__name__, logging.INFO)
logger = logging.getLogger(__name__)


def write_pkg_zip(zip_local_path: str, local_files: list, repo_root: str) -> None:
    """
    Builds a --py-files zip preserving each file's full repo-relative path
    (e.g. dags/agents/<dag>/spark_jobs/framework/x.py), so absolute imports
    like `dags.agents.<dag>.spark_jobs.framework.x` resolve on the EMR
    driver. Also writes an explicit directory entry for every intermediate
    namespace-package level: zipimport does not infer implicit namespace
    packages from a nested file's path alone the way a real filesystem does,
    so a zip with only `dags/__init__.py` + nested files 404s on import.
    """
    with zipfile.ZipFile(zip_local_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(path.join(repo_root, "dags", "__init__.py"), "dags/__init__.py")
        written_dirs = set()
        for local_file in local_files:
            arcname = path.relpath(local_file, repo_root)
            dir_parts = arcname.split("/")[:-1]
            for depth in range(1, len(dir_parts) + 1):
                dir_arcname = "/".join(dir_parts[:depth]) + "/"
                if dir_arcname not in written_dirs:
                    zf.writestr(dir_arcname, "")
                    written_dirs.add(dir_arcname)
            zf.write(local_file, arcname)


def upload_one_file(
    bucket: str, client: boto3.client, local_path: str, remote_path: str
):
    """
    Uploads a single file into S3. Used for multiple concurrent requests wchich
    share the same S3 client object.
    Args:
        bucket (str): S3 bucket where files will be uploaded into
        client (boto3.client): S3 client object
        local_path (str): Local dir where the file is placed
        remote_path (str): Remote S3 target object name
    """
    logger.info(f"Uploading file '{local_path}'")
    client.upload_file(
        local_path, bucket, remote_path, ExtraArgs={"ACL": "bucket-owner-full-control"}
    )
    logger.info(f"Uploaded file 's3://{bucket}/{remote_path}'")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(dest="s3_bucket")
    parser.add_argument(dest="artifact")
    parser.add_argument(
        "--include-dir",
        required=False,
        help="Only upload artifacts whose path is under dags/<DIR>/ (e.g. luigijr). Used by "
        "the luigijr esteira to sync ONLY its DAGs to the forno Databricks volume.",
    )
    parser.add_argument(
        "--exclude-dir",
        required=False,
        help="Skip artifacts whose path is under dags/<DIR>/ (e.g. luigijr). Mirrors the "
        "create_dag_files build barrier so the forno/prod volume never gets luigijr files.",
    )
    args = parser.parse_args()
    s3_bucket = args.s3_bucket
    artifact = args.artifact
    include_dir = args.include_dir
    exclude_dir = args.exclude_dir

    s3_dags_packages_path_prefix = path.join("github-repos/bi-etl-ejuice/", artifact)

    config = Config(retries={"max_attempts": 5, "mode": "standard"})
    session = boto3.Session()
    client = session.client("s3", config=config)
    func = partial(upload_one_file, s3_bucket, client)

    files_to_upload = []
    # dag_name -> every local file path under its spark_jobs/ tree (root-level
    # included, e.g. a top-level sibling module imported by the entry script).
    spark_job_files_by_dag = defaultdict(list)
    # dag_names whose spark_jobs package has subdirectories: nested absolute
    # imports like `dags.agents.<dag>.spark_jobs.framework.x` can't resolve
    # from flat --py-files, so only these get a structure-preserving pkg.zip.
    dags_with_nested_spark_jobs = set()

    for root, dirs, files in os.walk(DAG_PACKAGES_ROOT):
        if f"/{artifact}" not in root:
            continue
        if include_dir and f"/{include_dir}/" not in f"{root}/":
            continue
        if exclude_dir and f"/{exclude_dir}/" in f"{root}/":
            continue

        for file_name in files:
            dag_path, artifact_path = re.split(f"/{artifact}", root)
            dag_path = f"{dag_path}/"
            dag_name = "/".join(
                list(filter(None, dag_path.replace(DAG_PACKAGES_ROOT, "").split("/")))[
                    1:
                ]
            )

            spark_job_local_path = path.join(root, file_name)
            spark_job_s3_path = path.join(
                s3_dags_packages_path_prefix,
                dag_name,
                artifact_path.strip("/"),
                file_name,
            )
            files_to_upload.append((spark_job_local_path, spark_job_s3_path))

            if artifact == "spark_jobs":
                spark_job_files_by_dag[dag_name].append(spark_job_local_path)
                if artifact_path.strip("/"):
                    dags_with_nested_spark_jobs.add(dag_name)

    repo_root = path.dirname(DAG_PACKAGES_ROOT)
    tmp_zip_dir = tempfile.mkdtemp(prefix="spark_jobs_pkg_")
    for dag_name in dags_with_nested_spark_jobs:
        zip_local_path = path.join(tmp_zip_dir, f"{dag_name.replace('/', '_')}_pkg.zip")
        write_pkg_zip(zip_local_path, spark_job_files_by_dag[dag_name], repo_root)
        zip_s3_path = path.join(s3_dags_packages_path_prefix, dag_name, "pkg.zip")
        files_to_upload.append((zip_local_path, zip_s3_path))

    with tqdm(
        desc=f"Uploading {artifact} into S3", total=len(files_to_upload)
    ) as progress_bar:
        with ThreadPoolExecutor(max_workers=64) as executor:
            futures = {
                executor.submit(func, *file_to_upload): file_to_upload
                for file_to_upload in files_to_upload
            }
            for future in as_completed(futures):
                if future.exception():
                    raise future.exception()
                progress_bar.update(1)


if __name__ == "__main__":
    main()
