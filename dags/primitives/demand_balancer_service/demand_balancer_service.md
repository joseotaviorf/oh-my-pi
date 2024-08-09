## Demand Balancer

### Purpose

This DAG is responsible for loading prediction from our batch Demand Balancer model into our Data Lake.

Demand Balancer write data to a standardized bucket in s3, from which data will be loaded incrementally into our datalake

<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once a day.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG produces, via incremental load, the following tables in Raw layer:

- `demand_balancer`

</details>
