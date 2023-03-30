## Enrich Search Session Event
​
### Purpose
​
This DAG creates the enriched table that unites search session events from Amplitude, and makes their grain per house.
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following table in enrich layer, via incremental load:

- `search_session_event`

​</details>
