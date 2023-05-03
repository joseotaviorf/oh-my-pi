## Enrich CRM Tasks History Flows

Creates CRM (Customer Relationship Management) base tasks history table. These tables will be used to generate

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

- In datalake `enrich` layer (incremental load):
    * `tasks_history_resolutions_flow`
    * `tasks_history_users_flow`

</details>
