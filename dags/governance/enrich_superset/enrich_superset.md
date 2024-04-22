## Enrich Superset

### Purpose

This DAG creates the full table for Superset incremental tables.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table:

1. In data lake enrich:

- `ab_user`
- `dashboards`
- `slices`
- `sql_metrics`
- `table_columns`
- `table_schema`
- `tables`
- `tag`
- `tagged_object`

</details>