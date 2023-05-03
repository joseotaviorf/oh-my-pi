## Enrich CRM Tasks Flows

Creates CRM (Customer Relationship Management) base tasks flows tables. These tables will be used to generate models in Tasks context.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

- In datalake `enrich` layer (incremental load):
    * `tasks_actions_resolutions_flow`
    * `tasks_users_resolutions_flow`

</details>
