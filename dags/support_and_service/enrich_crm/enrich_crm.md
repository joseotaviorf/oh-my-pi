## Enrich CRM
### Purpose

Normalize and prepare CRM data for further enrichment.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
### Execution Interval

This DAG is triggered once per day via Mediator, after CRM extraction DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer:

- `tasks`
- `task_status_histories`
- `task_titles`
- `tasks_actions`
- `workflows_transitions`
- `workgroups`

</details>
