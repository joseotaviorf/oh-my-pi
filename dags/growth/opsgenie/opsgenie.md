## Opsgenie

### Purpose

This DAG collects data from OpsGenie, the 5A tool to manage on-call schedules, incidents, and alerts. More information about columns and labels can be found in [API documentation](https://docs.opsgenie.com/docs/alert-api).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

1. In datalake raw:
    - `datalake_opsgenie_raw.incidents`
    

2. In datalake clean:
    - `datalake_opsgenie_clean.incidents`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
  
</details>