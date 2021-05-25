## DW Front Tickets
### Purpose
​
This DAG load the DW tables for Front Tickets.
​
### Execution​ Interval
This DAG is triggered once per day via Mediator, after enrich_front_tickets DAG

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables in `front_tickets` schema:
​
- `fact_ticket`
- `fact_task`
- `dim_agent`
- `dim_department`
- `dim_taxonomy`
- `dim_channel`

​
### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
