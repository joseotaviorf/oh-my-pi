## Enrich CRM Lead
### Purpose

Creates enriched tables for the context `Lead` and `CRM`.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer:

- `lead_score_factor`
- `lead_tasks`

</details>
