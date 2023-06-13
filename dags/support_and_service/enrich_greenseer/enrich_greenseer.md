## Enrich Greenseer

### Purpose

Extract relevant fields from greenseer memory json and add relevant business rules to reduce the analysis.

### Execution Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer (via full load):

- `greenseer_session`
- `session_memory`
