## Search Metrics

### Purpose

This DAG is responsible for loading prediction from our batch Search Metrics into our Data Lake.

Search Monitoring writes data to a standardized bucket in s3, from which data will be loaded incrementally into our datalake and then read by Superset

<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once per day.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG produces, via incremental load, the following tables in Raw layer:

- `search_monitoring/metrics`

</details>
