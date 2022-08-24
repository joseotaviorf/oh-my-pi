## Datamarts For Rent Cross

### Purpose

Creates/updates the datamart tables

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the following full tables in the schema `dw_datamarts` of data lake:

- `rental_demand_events_funnel_flows`
- `rental_events_funnel`
- `rental_events_funnel_partners`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data For Rent team.

### Additional Information

The file [for_rent_cross.yml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/dags/dw_datamarts_spark/for_rent_cross/for_rent_cross.yml)
declares the datamarts that should be created in this DAG.

So **to add/remove a datamart table** from the DAG you only need to **update this file**.

</details>
