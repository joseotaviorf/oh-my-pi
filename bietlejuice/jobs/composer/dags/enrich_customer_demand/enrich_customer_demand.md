## Enrich Customer Demand
### Purpose

Tranform and centralize tasks from different sources to calculate the backoffice demand and SLA rate.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on Enrich layer:

- `base_tasks` (full load)
- `demand_metrics` (full load)
- `backlog_metrics` (full load)
- `ra_data` (full load)

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering team responsible.

</details>