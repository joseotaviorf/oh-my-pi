## Enrich Sale Listings Scores

### Purpose

The purpose of this DAG is to materialize the analysis made by the ForSale Supply team. With it, we will create some tiers where we will classify the listings. We will use it to have very clear leverage on the state of the listing.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is intended to run daily.

- The `premium_lens` table is intended to classify a property on what premium it is for its location. After analysis we arrive at a metric that takes into account the price and the price per m2.
- The `princing_lens` table is intended to rank the listings according to the price published by the Seller. If this price is very different from what we estimated in the ForSale Calculator, we will classify as a different tier for those well priced.
- The `demand_lens` table is intended to classify a property in what demand . After analysis we arrive at a metric that takes into account the number of visits and the number of contacts.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following tables in enrich layer:

Via **Full Load**:
    - `premium_lens`
    - `pricing_lens`
    - `demand_lens`

</details>
