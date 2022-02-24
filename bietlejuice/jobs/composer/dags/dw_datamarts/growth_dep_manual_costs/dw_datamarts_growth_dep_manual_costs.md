## Datamarts Growth - Manual Costs Dependents

### Purpose

Creates/updates the datamart tables in data lake and DW, for the context of Growth, that depends on the table 
`datalake_marketing_costs_prod.daily_costs`.
This table has 2 partitions -> flow_type = `manual` and flow_type = `automatic`.
Today we have 2 DAGs updating these partitions, the DAG enrich_marketing_automatic_daily_costs updates the partition flow_type = `automatic` and the DAG enrich_marketing_manual_daily_costs updates the partition flow_type = `manual`.

We need to duplicate datamarts execution that depends on this table because the automatic costs are available all days around 5:30 am
but the manual costs are only available around 11:00 am, and the stakeholders can't wait to access automatic costs until 11:00 am.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the tables in the schema `dw_datamart` of data lake and `datamarts` of DW.

### Additional Information

The file [dw_datamarts_growth_dep_manual_costs_prod_conf.yml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/jobs/composer/dags/dw_datamarts/growth/dw_datamarts_growth_dep_manual_costs_prod_conf.yml)
declares the datamarts that should be created in this DAG.
So **for add/remove a datamart table** from the DAG you only need to **update this file**.