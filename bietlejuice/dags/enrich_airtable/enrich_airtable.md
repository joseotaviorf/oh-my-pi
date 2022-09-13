## Enrich Airtable

### Purpose

Creates enriched tables for airtable. For now, it is only deduplicating data from the
clean layer and bringing the last state of agents information. 

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table:

- `activated`
- `activations`
- `cr_occurrences`
- `jira_tickets`
- `leads`


</details>