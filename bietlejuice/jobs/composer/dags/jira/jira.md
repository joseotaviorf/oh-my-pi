## Jira

### Purpose
This DAG imports, via API extraction, the tables for Jira, our platform for managing project lifecycles.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces, in datalake raw and clean, all the tables available in the following endpoints:

- `projects` (full load)
- `issues` (incremental load)

### Responsible Data Engineering Team
For any questions or concerns about this DAG, please contact the Dag Owner Team.

### Additional Information
- [JIRA API doc](https://jira.readthedocs.io/en/master/api.html)

</details>