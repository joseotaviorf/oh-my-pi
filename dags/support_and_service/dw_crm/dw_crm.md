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


- `crm.dim_closing_task_transition`
- `crm.dim_closing_task_workflow`
- `crm.dim_collection_task`
- `crm.dim_credit_task`
- `crm.dim_inspection_task`
- `crm.dim_lead_task`
- `crm.dim_linhadireta_chat_task`
- `crm.dim_offboarding_task`
- `crm.dim_onboarding_tenant_task`
- `crm.dim_payment_task`
- `crm.dim_photo_job_task`
- `crm.dim_repair_task`
- `crm.dim_ungrouped_manual_task`
- `crm.dim_visit_task`
- `crm.fact_closing_tasks_workflows_transitions`
- `crm.fact_linhadireta_chat_tasks`
- `crm.fact_credit_tasks`
- `crm.fact_inspection_tasks`
- `crm.fact_lead_tasks`
- `crm.fact_offboarding_tasks`
- `crm.fact_payment_tasks`
- `crm.fact_repair_tasks`
- `crm.fact_ungrouped_manual_tasks`
- `crm.fact_visit_tasks`
- `crm.fact_lead_task_actions`


### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>
