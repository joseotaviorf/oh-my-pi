## Enrich Sale Buyer Journey
​
### Purpose
​
This DAG creates the enriched tables to Sale Journey, getting all data about the demand ForSale context.
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following table in enrich layer, via full load:

- `hub_services_contact`
- `sale_journey`

And via incremental load:

- `amplitude_sale_contact`
​
​</details>
