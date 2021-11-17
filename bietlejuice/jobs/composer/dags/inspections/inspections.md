## Inspections
### Purpose

Retrieves data from the Inspections database (PostgreSQL). [Inspections](https://github.com/quintoandar/inspections-service) is a micro service to inspections with this database we need to measure the lead time inspections, when inspector start and finish inspection, if he follow the planner's route.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following tables into the datalake Raw and Clean:

1. Via full load:
- `item_group_type`
- `item_type`
- `room_type`

2. Via incremental load:
- `access_info`
- `access_info_aud`
- `inspection`
- `inspection_aud`
- `item_group_type_aud`
- `item_type_aud`
- `rev_info`
- `room_type_aud`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>