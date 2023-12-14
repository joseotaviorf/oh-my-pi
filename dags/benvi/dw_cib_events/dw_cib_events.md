## DW CIB Events

### Purpose

This DAG creates tables that summarize the CIB's events.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily at 1pm. More information about run time [here]({chart_url}{dag_id})

### Outputs

This pipeline produces the following output table in DW layer, via incremental load:

- `dw_cib_events.fact_cib_events`
