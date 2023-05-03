## Datamarts For Sale

### Purpose

Creates/updates the datamart tables that don't have cross squad dependencies, for the context of Sales, in data lake and DW.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the tables in the schema `dw_datamart` of data lake and `datamarts` of DW.

### Additional Information

The [configuration file](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/for_sale/dw_datamarts_for_sale/prod_conf.yml)
declares the datamarts that should be created in this DAG.
So **for add/remove a datamart table** from the DAG you only need to **update this file**.
