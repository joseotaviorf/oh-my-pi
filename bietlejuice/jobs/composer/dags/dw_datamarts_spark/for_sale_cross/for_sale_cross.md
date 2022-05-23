## Datamarts For Sale Cross

### Purpose

Creates/updates the datamart tables that have cross squad dependencies, for the context of Sales, in data lake.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the following full tables in the schema `dw_datamarts` of data lake:

- `sale_cohort_conversions`
- `temp_supply_flows`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data For Sale team.

### Additional Information

The file [for_sale_cross.yml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/jobs/composer/dags/dw_datamarts_spark/for_sale_cross/for_sale_cross.yml)
declares the datamarts that should be created in this DAG.
So **to add/remove a datamart table** from the DAG you only need to **update this file**.
