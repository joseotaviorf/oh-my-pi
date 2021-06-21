## Enrich CRM Tasks Resolution

Creates CRM (Customer Relationship Management) tasks resolution tables which union actions and status histories from CRM tasks in enrich `datalake_crm` layer and loads them into datalake enrich `datalake_crm_tasks_resolution` layer.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

- In datalake `enrich` layer:
    * `datalake_crm_tasks_resolution.tasks_resolution` (Full load)
    * `datalake_crm_tasks_resolution.tasks_resolution_history` (Full load)
    
### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>