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

## sql_transcript

```sh
# Quick start - transpile all new/modified SQL files
make transcript-sql-files

# Or use the script directly:
python sql_transcript.py --mode git-diff --from-branch origin/master --to-branch HEAD

# Transcript a specific SQL file
python sql_transcript.py --mode single-file --file path/to/file.sql

# Transcript all SQL files in a directory
python sql_transcript.py --mode directory --directory dags/support_and_service

# Dry run (show changes without writing)
python sql_transcript.py --mode git-diff --from-branch origin/master --to-branch HEAD --dry-run
```

### What?

Converts SQL files from Trino syntax to Databricks syntax using sqlglot. This script automatically transpiles SQL queries to ensure compatibility with Databricks' SQL dialect. **The script edits SQL files in place**, making them ready for Databricks execution.

### Where?

This script can be used in CI/CD pipelines to automatically transpile SQL files when they are created or modified. It supports three modes:
- **git-diff**: Transpile only new or modified SQL files in a git diff
- **single-file**: Transpile a specific SQL file
- **directory**: Transpile all SQL files in a directory recursively

**CI/CD Integration:** The script is configured in `.woodpecker/validations.yml` to run automatically when SQL files in `dags/planning_and_performance/` are modified. The CI can also auto-commit transpiled files back to the repository.

### How?

The script uses the `sqlglot` library (version 26.9.0) to parse SQL in Trino syntax and convert it to Databricks syntax. It provides:
- **In-place file editing**: Directly updates SQL files with Databricks syntax
- **Custom replacements**: Automatically replaces `CURRENT_DATE` with `DATE('{load_start_date}')`
- Automatic detection of new/modified SQL files using `GitService`
- Dry-run mode to preview changes before applying them
- Detailed summary reporting with success, error, and unchanged file counts
- Error handling and logging for debugging failed transpilations