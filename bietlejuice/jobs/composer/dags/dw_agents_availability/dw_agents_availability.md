## DW Agents Availability

### Purpose

This DAG creates tables that summarize the agent availability. For while, there is one table named fact_inspector_allocations that has information about agents slots with one hour as grain, in addition.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This dag is triggered once per day via Mediator. More information about run time [here]({chart_url}{dag_id})

### Outputs

This pipeline produces the following output tables: 

- `agents_availability.fact_inspector_allocations`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>
