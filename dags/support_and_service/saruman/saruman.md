## Saruman
### Purpose

Retrieves data from the Saruman database (PostgreSQL).

[Saruman](https://github.com/quintoandar/saruman) is a service that concentrates events from multiple sources and builds a timeline used to provide context for support sessions. Some of these events are tagging, routing, creation, ending, comment events about a session and about workflows.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following tables into the datalake:

- `session` (incremental load)
- `session_history` (incremental load)
- `pendency` (incremental load)
- `support_case` (full load)

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact its owner.

</details>
