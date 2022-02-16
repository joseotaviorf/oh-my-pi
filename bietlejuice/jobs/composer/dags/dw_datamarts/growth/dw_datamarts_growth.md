## Datamarts Growth

### Purpose

Creates/updates the datamart tables, for the context of Growth, in data lake and DW.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the tables in the schema `dw_datamart` of data lake and `datamarts` of DW.

### Additional Information

The file [dw_datamarts_growth_prod_conf.yml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/jobs/composer/dags/dw_datamarts/growth/dw_datamarts_growth_prod_conf.yml)
declares the datamarts that should be created in this DAG.
So **for add/remove a datamart table** from the DAG you only need to **update this file**.
