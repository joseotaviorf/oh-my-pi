## Enrich Mexico MOX Reports

### Purpose
This DAG has the goal to load the MOX's reports.

<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output table in the enrich layer, via incremental load:

- `imss`
- `imss_work_history`

</details>
