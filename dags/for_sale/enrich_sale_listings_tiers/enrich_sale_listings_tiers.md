## Enrich Sale Listings Scores

### Purpose

The purpose of this DAG is to materialize the analysis made by the ForSale Supply team. With it, we will create some tiers where we will classify the listings. We will use it to have very clear leverage on the state of the listing.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is intended to run daily.

- The `premium_tier` table is intended to classify a property on what premium it is for its location. After analysis we arrive at a metric that takes into account the price and the price per m2.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following tables in enrich layer:

Via **Full Load**:
    - `premium_tier`

</details>
