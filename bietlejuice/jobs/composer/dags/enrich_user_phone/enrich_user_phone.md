## Enrich User Phone
### Purpose

Prepares EBDB ([Main's](https://github.com/quintoandar/main) database) data for further utilization on DW Call tables.

### Execution Interval

This DAG is triggered once per day, usually around 7:30 A.M. UTC. This is **NOT** triggered by Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables on the enrich layer:

- `dialed_user_phone`
- `incoming_user_phone`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
