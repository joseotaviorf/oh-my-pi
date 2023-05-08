## Enrich Sale Offer
​
### Purpose
​
This DAG creates the enriched table for Sale Offer, getting all data about the offer ForSale context.
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following table in enrich layer, via full load:

- `sale_offer`
​
