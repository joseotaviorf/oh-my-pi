## Inspections
### Purpose

Retrieves data from the Inspections database (PostgreSQL). [Inspections](https://github.com/quintoandar/inspections-service) is a micro service to inspections with this database we need to measure the lead time inspections, when inspector start and finish inspection, if he follow the planner's route.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following tables into the datalake Raw and Clean via Full load:

- `assessment`
- `assessment_aud`
- `inspection`
- `inspection_aud`
- `issue_type`
- `item_group_type`
- `item_type`
- `room_type`
- `rev_info`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact its owner.

</details>