## Looker


### Purpose
Extracts data from Looker assets metadata

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs
We incrementally load the following tables into the datalake Raw and Clean:

- Raw
  - `datalake_looker_raw.users`
  - `datalake_looker_raw.folders`
  - `datalake_looker_raw.dashboards`
  - `datalake_looker_raw.dashboard_elements`

- Clean
  - `datalake_looker_clean.users`
  - `datalake_looker_clean.folders`
  - `datalake_looker_clean.dashboards`
  - `datalake_looker_clean.dashboard_elements`

</details>
