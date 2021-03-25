## Enrich CRM
### Purpose

Normalize and prepare CRM data for further enrichment.

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

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
