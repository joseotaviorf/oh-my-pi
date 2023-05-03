## Enrich Sale Closing Flows
​
### Purpose
​
This DAG creates the enriched table for Sale Closing Flows, in order to create metrics for monitor and analyze the closing funnel in For Sale.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
​
### Execution​ Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following table in enrich layer, via full load:
    - `closing_flow`
​
</details>
