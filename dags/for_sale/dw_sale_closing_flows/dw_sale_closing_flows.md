## DW Sale Closing Flows

### Purpose

This DAG creates the model for Sale Closing Flows.
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline is responsible for creating the following tables in the DW schema `sale`, via full load:

- `fact_closing_flows`

</details>
