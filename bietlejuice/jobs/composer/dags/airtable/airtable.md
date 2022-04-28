## Airtable

### Purpose
This DAG creates the raw and clean layer for tables from Airtable. Airtable is a platform that enables
us to manipulate data with the same flexibility of a sheet, but with a relational database in the
background. 

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output table in the raw and clean layers:

- Via incremental load:
    - `activated`
    - `jira_tickets`

</details>