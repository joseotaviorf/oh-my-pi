## Enrich Sirena
​
### Purpose
​
This DAG creates the enriched table for Sirena, getting all data about the manual messages and flat some jsons structs.
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following table in enrich layer, via full load:

- `messages`
​
​</details>
