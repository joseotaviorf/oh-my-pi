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

- `fact_ticket`
- `fact_segment`
- `fact_csat`
- `fact_agent_daily_achievement` (incremental load)
- `fact_agent_daily_productivity` (incremental load)
- `dim_ranking_targets`
- `dim_agent`
- `dim_department`
- `dim_taxonomy`
- `dim_channel`

​
### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>