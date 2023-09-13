## Enrich Sale Visit
​
### Purpose
​
This DAG creates the enriched table for Sale Visit, getting all data about the visit ForSale context that will be used in other enrichs and fact tables.
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following table in enrich layer, via full load:

- `sale_visit`
​
