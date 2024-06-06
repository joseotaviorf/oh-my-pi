## DW Rent Flow

### Purpose

This DAG loads to DW our models of rent flows.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW:

- `dw_public.fact_listing_rent_flows`
