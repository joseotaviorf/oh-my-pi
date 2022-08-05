## Enrich BigID

### Purpose

Creates enriched tables for `BigID`.

BigID is a data governance tool used to catalog product databases and automatically classify if
their data is PII, sensitive, etc.

This enrich DAG output is used by the `catalog_product_entities` DAG to create product entities in
the data catalog.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Weekly. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables (full load):

- `bigid_entities_access_level`

</details>
