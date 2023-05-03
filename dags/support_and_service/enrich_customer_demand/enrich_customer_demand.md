## Enrich Customer Demand
### Purpose

Tranform and centralize tasks from different sources to calculate the backoffice demand and SLA rate.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on Enrich layer:

- `backlog_metrics` (full load)
- `base_tasks` (full load)
- `base_tasks_metrics` (incremental load)
- `demand_metrics` (full load)
- `demand_metrics_tasks` (full load)
- `quality_metrics` (full load)
- `ra_metrics` (full load)

</details>
