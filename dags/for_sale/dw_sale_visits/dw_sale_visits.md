## DW Sale Visits

### Purpose

This DAG creates the model for Sale Visits via full loading.

### Execution Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline is responsible for creating the following tables in the DW schema `sale`:

- `fact_visits`
