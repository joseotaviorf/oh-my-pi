## Datamarts For Sale Cross

### Purpose

Creates/updates the datamart tables with cross squad datamart dependencies, for the context of Sales, in data lake and DW.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the tables in the schema `dw_datamart` of data lake and `datamarts` of DW.

### Additional Information

The file [datamarts.yaml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/dags/datamarts/datamarts.yml)
declares the datamarts that should be created in this DAG.
So **for add/remove a datamart table** from the DAG you only need to **update this file**.
