## DW Rent Demand Events

### Purpose

This DAG loads to DW the fact table for the rent demand events: fact_rent_demand_events

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW, via full load :

- `dw_rent_demand_events.fact_rent_demand_events`
