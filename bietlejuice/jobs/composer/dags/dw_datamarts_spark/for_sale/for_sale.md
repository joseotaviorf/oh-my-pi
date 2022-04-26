## Datamarts For Sale

### Purpose

Creates/updates the datamart tables that don't have cross squad dependencies, for the context of Sales, in data lake.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the tables in the schema `dw_datamart` of data lake.

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data For Sale team.

### Additional Information

The file [datamarts.yaml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/jobs/composer/dags/dw_datamarts_spark/for_sale/for_sale.yml)
declares the datamarts that should be created in this DAG.
So **to add/remove a datamart table** from the DAG you only need to **update this file**.
