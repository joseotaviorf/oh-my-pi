## Enrich Braze Events User Centric
​
### Purpose
​
This DAG creates the incremental enriched table for Braze user centric events with every campaign/canvas groupped daily.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator, after enrich_braze_events DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output table:
​
- `user_events_daily` – Contains information about events of all types of Braze users.
​
​</details>
