# CI/CD Scripts

## upload_dag_packages_artifact_into_s3

```sh
python upload_dag_packages_artifact_into_s3.py [S3_BUCKET] [ARTIFACT: queries|spark_jobs|data_quality]
```

### What?

  Uploads to a provided S3 bucket all files of a specific artifact type related to DAG pipelines, from within bi-etl-ejuice repository. These artifacts will be used by DAGs in environments where data transformation or quality assurance occurs, like Databricks.

### Where?

  This script is used in the following CI steps:

- `upload-dag-packages-spark-jobs-s3-forno`
- `upload-dag-packages-spark-jobs-s3-new-forno-account`
- `upload-dag-packages-spark-jobs-s3-prod`
- `upload-dag-packages-spark-jobs-s3-new-prod-account`
- `upload-dag-packages-queries-s3-forno`
- `upload-dag-packages-queries-s3-new-forno-account`
- `upload-dag-packages-queries-s3-prod`
- `upload-dag-packages-queries-s3-new-prod-account`

### How?

  The script walks through the DAG folder structure, retrieving all files below the tree path containing the `ARTIFACT` argument. It uploads the files to S3 concatenating the subpaths according to predefined DAG and context naming conventions. The upload requests are performed concurrently using threads, to maximize throughtput. Retries are configured natively using `boto3` configs. For more information about retries, please refer to [`boto3` Standard retry mode docs].

[`boto3` Standard retry mode docs]: https://boto3.amazonaws.com/v1/documentation/api/latest/guide/retries.html#standard-retry-mode
