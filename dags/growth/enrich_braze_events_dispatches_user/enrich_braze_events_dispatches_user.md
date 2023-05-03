## Enrich Braze Events Dispatches User

### Purpose
This DAG creates the incremental enriched tables for dispatches for both tenants and owners users from Braze.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output tables, on enrich layer:

    - `owners_events`
    - `tenants_events`

</details>
