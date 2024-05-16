## Datamarts For Rent

### Purpose

Creates/updates the datamart tables that don't have cross squad dependencies, for the context of Rent, in data lake.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the following full tables in the schema `dw_datamarts` of data lake:

- `house_weekly_available_hours`
- `ongoing_listed_suspended_listings`
- `repressed_demand`
- `repressed_demand_booking_fit_in`

### Additional Information

The file [for_rent.yml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/cross/dw_datamarts_spark/for_rent/for_rent.yml)
declares the datamarts that should be created in this DAG.
So **to add/remove a datamart table** from the DAG you only need to **update this file**.

</details>
