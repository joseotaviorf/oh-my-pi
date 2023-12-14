## DW CIB Segmentation

### Purpose

This DAG creates tables that summarize the CIB's segmentation.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered in the first day of the month, via Mediator. More information about run time [here]({chart_url}{dag_id})

### Outputs

This pipeline produces the following output table in DW layer:

- `dw_cib_segmentation.dim_cib_segmentation`
- `dw_cib_segmentation.fact_cib_segmentation`
