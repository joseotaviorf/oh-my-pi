## Datamarts For Rent Cross

### Purpose

Creates/updates the datamart tables

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the following full tables in the schema `dw_datamarts` of data lake:

- `pricing_rent_categorization`
- `rental_cohort_conversions`
- `rental_marketplace_flows`

### Additional Information

The file [for_rent_cross.yml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/cross/dw_datamarts_spark/for_rent_cross/for_rent_cross.yml)
declares the datamarts that should be created in this DAG.

So **to add/remove a datamart table** from the DAG you only need to **update this file**.

</details>
