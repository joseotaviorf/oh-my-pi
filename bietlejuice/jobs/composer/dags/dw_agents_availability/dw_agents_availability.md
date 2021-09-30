## DW Agents Availability

### Purpose

This DAG creates tables that summarize the agent availability. For while, there are two tables - fact_inspector_hourly_allocations that has information about agents slots with one hour as grain, and fact_inspector_daily_allocations with day as grain.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This dag is triggered once per day via Mediator. More information about run time [here]({chart_url}{dag_id})

### Outputs

This pipeline produces the following output tables: 

- `agents_availability.fact_inspector_daily_allocations`
- `agents_availability.fact_inspector_hourly_allocations`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>
