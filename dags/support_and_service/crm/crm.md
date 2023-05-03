## CRM

Retrieves data from CRM (Customer Relationship Management) and load it on datalake.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

1. In datalake raw:

    * tasks (incrementally)
    * taskstatushistories (incrementally)
    * workflows (incrementally)
    * workgroups
    * tasktitles

2. In datalake clean

    * tasks (incrementally)
    * task_status_histories (incrementally)
    * workflows (incrementally)
    * workgroups
    * task_titles

</details>
