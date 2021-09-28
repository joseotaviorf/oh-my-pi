## DW CRM
### Purpose

Creates DW fact and dimension tables for CRM context. 

<details>
    <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output tables in DW layer, via incremental load: 

- `crm_migration.dim_closing_task_transition`
- `crm_migration.dim_closing_task_workflow`
- `crm_migration.dim_offboarding_task`
- `crm_migration.dim_ungrouped_manual_task`
- `crm_migration.fact_closing_tasks_workflows_transitions`
- `crm_migration.fact_offboarding_tasks`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>