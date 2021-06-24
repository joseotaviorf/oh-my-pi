## TROVIT

### Purpose

This dag uses data extracted from Lifull in the old flow (EC2) and brings to the new clean layer.

<details>
    <summary><strong> > DAG details (click to expand)</strong></summary>

### Dag Dependencies
This DAG depends on the old flow temporarily, the EC2 DAG is [bi-marketing-costs](https://airflow.quintoandar.com.br/admin/airflow/tree?dag_id=bi-marketing-costs). It runs an AWS Batch script that lives in [this repo](https://github.com/quintoandar/trovit-spider) and uses [this client](https://github.com/quintoandar/python-utils/blob/master/qa_python_utils/aws/batch.py).

### Dependent Dags
- [bietlejuice.dw_marketing_costs_trovit](https://k6ead11b55326f9c9-tp.appspot.com/admin/airflow/tree?dag_id=bietlejuice.dw_marketing_costs_trovit).

### Execution Interval
This dag is triggered once per day 6 AM BRT.

### Outputs
- datalake_trovit_clean.trovit_report

### Responsible Data Engineering Team
For any questions or concerns, please contact the Data Marketing Team.

### Major Changes (JIRA Tasks)
[DTM-610](https://quintoandar.atlassian.net/jira/software/projects/DTM/boards/417?selectedIssue=DTM-643)
</details>