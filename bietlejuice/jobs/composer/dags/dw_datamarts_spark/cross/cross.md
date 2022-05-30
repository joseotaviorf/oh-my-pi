## Datamarts Cross

### Purpose

Creates/updates the datamart tables for cross squad contexts in datalake.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the following full tables in the schema `dw_datamarts` of data lake:

- `buyer_prospect_status`
- `quintoandar_consultant_listings`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering team.

### Additional Information

The file [cross.yml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/jobs/composer/dags/dw_datamarts_spark/cross/cross.yml)
declares the datamarts that should be created in this DAG.
So **to add/remove a datamart table** from the DAG you only need to **update this file**.
