## Enrich Trino


### Purpose
Exports Trino usage data from data_platform_metrics table in Databricks

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs
We incrementally load the following tables into the datalake Enrich layer:

- Enrich
  - `datalake_trino.table_usage_information`

</details>
