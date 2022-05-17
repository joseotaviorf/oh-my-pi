## Datamarts Support and Service

### Purpose

Creates/updates the datamart tables that don't have cross squad dependencies, for the context of Support and Service, in data lake.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the following full tables in the schema `dw_datamarts` of data lake:

- `house_media`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Support and Service team.

### Additional Information

The file [support_and_service.yml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/jobs/composer/dags/dw_datamarts_spark/support_and_service/support_and_service.yml)
declares the datamarts that should be created in this DAG.
So **to add/remove a datamart table** from the DAG you only need to **update this file**.
