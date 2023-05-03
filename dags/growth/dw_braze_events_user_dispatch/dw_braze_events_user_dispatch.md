## DW Braze Events User Dispatch
​
### Purpose
​
This DAG creates the incremental modelings for Braze Events, context User Dispatch.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces in DW schema `braze`:
    - incremental load:
        - `fact_braze_campaign_user_dispatch`
        - `fact_braze_canvas_user_dispatch`
    - full load:
        - `dim_campaign`
        - `dim_canvas`
​
​</details>
