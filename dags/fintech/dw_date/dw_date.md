## DW Date

### Purpose

This DAG loads to DW our base date dimension.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW:

- `dw_public.dim_date`

</details>
