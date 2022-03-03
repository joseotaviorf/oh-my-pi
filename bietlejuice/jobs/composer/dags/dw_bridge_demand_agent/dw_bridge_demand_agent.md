## DW Bridge Demand Agent

### Purpose

This DAG loads bridge demand agent to DW in schema public. The table *bdg_listing_rent_flows_agent_daily_allocations* 
connects a realized visit with an agent slot.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW, via full load: 

- `dim_bdg_listing_rent_flows_agent_daily_allocations`

</details>