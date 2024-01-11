## Enrich Sale Firestore

### Purpose
This DAG created enriched tables from Firestore data, for ForSale. Today it is only used for historical data.
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator, after `firestore` DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following tables in enrich layer, via full load:
- `monday`
- `sale_offer`

​</details>
