## Opsgenie

### Purpose

This DAG collects data from AlertManager, a tool to create alerts from Prometheus monitoring data. Currently, the data are collected from S3 bucket.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

1. In datalake raw:
    - `datalake_alert_manager_raw.alerts`


2. In datalake clean:
    - `datalake_alert_manager_clean.alerts_databricks_cluster`

</details>
