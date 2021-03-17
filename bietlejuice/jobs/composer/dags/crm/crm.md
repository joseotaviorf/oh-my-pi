## CRM

Retrieves data from CRM (Customer Relationship Management) and load it on datalake.

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
    
### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
