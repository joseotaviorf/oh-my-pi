## Jira

### Purpose
This DAG imports, via API extraction, the tables for Jira, our platform for managing project lifecycles.

### Execution Interval
This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces, in datalake raw and clean, all the tables available in the following endpoints:

- `projects` (full load)
- `issues` (incremental load)

### Responsible Data Engineering Team
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

### Additional Information
- [JIRA API doc](https://jira.readthedocs.io/en/master/api.html)