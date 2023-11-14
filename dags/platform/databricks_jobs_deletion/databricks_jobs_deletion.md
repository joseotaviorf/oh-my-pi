# Databricks Jobs Deletion

### Purpose

Creates a task per project that deletes Databricks jobs created over Jobs API 2.1 that are older than the provided `JOBS_REMOVAL_TIMEDELTA` and which name matches the RegExp provided in `PROJECT_TO_JOB_NAME_REGEX_MAPPING` variable. Uses DatabricksHook to directly call the jobs list API.

Built due to a Databricks resource limitation of 10,000 saved jobs per Workspace.

Executes every night before the first pipeline execution, to assure that the limit has not been reached when jobs start.

### References

- [Databricks resource limits](https://docs.databricks.com/resources/limits.html#limits)
- [Databricks Jobs API 2.1 list request](https://docs.databricks.com/api/workspace/jobs/list)
