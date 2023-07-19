# Databricks Jobs Deletion

### Purpose

Deletes Databricks jobs created over Jobs API 2.1 that are older than the provided `JOBS_REMOVAL_TIMEDELTA` and contains the provided `BIETLEJUICE_JOB_PREFIX` name filter. Uses DatabricksHook to directly call the jobs list API.

Built due to a Databricks resource limitation of 10,000 saved jobs per Workspace.

Executes every night before the first pipeline execution, to assure that the limit has not been reached when jobs start.

### References

- [Databricks resource limits](https://docs.databricks.com/resources/limits.html#limits)
- [Databricks Jobs API 2.1 list request](https://docs.databricks.com/api/workspace/jobs/list)
