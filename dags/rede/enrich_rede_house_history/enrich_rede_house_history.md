## Enrich Rede House History
​
### Purpose
​
This DAG creates the enriched table that tells us the history of how a house was or was not in Rede.
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following table in enrich layer, via full load:

- `rede_house_history`

​</details>
