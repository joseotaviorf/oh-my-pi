## Datamarts For Rent

### Purpose

Creates/updates the datamart tables, for the context of Rental, in data lake and DW.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the following full tables in the schema `dw_datamart` of data lake and `datamarts` of DW:

- `agents_activations_suspensions_contracts_changes`
- `contract_termination`
- `datamart_cohort_rentals`
- `datamart_kpi_weekly`
- `datamart_opportunity`
- `house_available_hours`
- `house_weekly_available_hours`
- `house_weekly_entrance_info`
- `ongoing_listed_suspended_listings`
- `repressed_demand`
- `weekly_demand_metrics`
  
### Additional Information

The file [datamarts.yaml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/jobs/composer/dags/datamarts/datamarts.yml)
declares the datamarts that should be created in this DAG.
So **for add/remove a datamart table** from the DAG you only need to **update this file**.
