## DW Listing Jobs

### Purpose

This DAG loads to DW our models related to the listings jobs.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW, via full load:

- `dim_inspection`
- `dim_photo_job`
- `fact_photo_job`
- `fact_inspection_bookings`

</details>
