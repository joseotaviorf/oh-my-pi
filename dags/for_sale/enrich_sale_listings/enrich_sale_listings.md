## Enrich Sale Listings

### Purpose
This DAG creates the enriched tables for Sale Listings context.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following tables in enrich layer, via full load:

    - `sale_listing`
    - `sale_listing_price_changes`
    - `sale_listings_status`
    - `sale_status_version_order`

</details>
