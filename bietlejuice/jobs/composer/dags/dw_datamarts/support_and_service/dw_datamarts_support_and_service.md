## Datamarts Support And Service

### Purpose

Creates/updates the datamart tables, for the context of Support and Service, in data lake and DW.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the tables in the schema `dw_datamart` of data lake and `datamarts` of DW.

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible.

### Additional Information

The file [datamarts.yaml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/jobs/composer/dags/dw_datamarts/support_and_service/dw_datamarts_support_and_service_prod_conf.yml)
declares the datamarts that should be created in this DAG.
So **for add/remove a datamart table** from the DAG you only need to **update this file**.
