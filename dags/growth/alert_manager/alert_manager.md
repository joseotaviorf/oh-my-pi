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

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
  
</details>