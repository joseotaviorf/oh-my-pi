## Enrich EBDB Agents

### Purpose

Creates enriched tables for the context `Agents` of ebdb. Mainly, related to agents availability/slots.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:

- `agent_business_context_history`
- `agent_contract`
- `agent_region_group`
- `agents_region`
- `agents_review`
- `agents_specific_weekly_schedule`
- `agents_weekly_schedule_history`
- `rating_label`
- `slots_base_time`

And via incremental load:
- `agents_activations_suspensions_contracts_changes`
- `agents_slots`
- `agents_slots_hourly`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
