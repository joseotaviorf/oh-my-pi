## DW Search Session Event

### Purpose

This DAG creates the model for search session events, from Amplitude.

### Execution Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline is responsible for creating the following tables in the DW schema `rede`:

- `dim_search_session_event_type`
- `fact_search_session_event`