## DW House

### Purpose

This DAG loads to DW our model dim_house, referent to house context.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW:

- `dim_house` – Contains information about property listings. Each line is a listing version.
- `dim_house_amenities` - Contains information about property amenities. Each line has all the most recent amenities of a house.
- `dim_house_status` – Contains information about property status and it's SK. Each line is a house status.


