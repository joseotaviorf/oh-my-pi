## DW Rent Demand Events

### Purpose

This DAG loads to DW the models related to rent demand events on schema `dw_rent`.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables in DW, via full load on `dw_rent` schema:

- `dw_rent.dim_rent_cohort_conversion_type`
- `dw_rent.dim_rent_event_type`
- `dw_rent.fact_rent_cohort_conversions`
- `dw_rent.fact_rent_demand_events`
