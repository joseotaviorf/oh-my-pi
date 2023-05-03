## DW Customer Support
### Purpose
​
This DAG load the DW tables for Customer Support.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>​

### Execution​ Interval
This DAG is triggered once per day via Mediator, after enrich_customer_support DAG

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables in `customer_support` schema

- `dim_agent` (full load)
- `dim_channel` (full load)
- `dim_department` (full load)
- `dim_ranking_targets` (full load)
- `dim_taxonomy` (full load)
- `dim_ticket_tags` (full load)
- `fact_agent_daily_productivity` (incremental load)
- `fact_agent_ranking` (incremental load)
- `fact_backlog_metrics_tasks` (full load)
- `fact_demand_metrics_tasks` (full load)
- `fact_segment` (full load)
- `fact_ticket` (full load)

</details>
