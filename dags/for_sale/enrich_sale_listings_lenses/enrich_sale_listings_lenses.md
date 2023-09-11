## Enrich Sale Listings Scores

### Purpose

The purpose of this DAG is to materialize the analysis made by the ForSale Supply team. With it, we will create some tiers where we will classify the listings. We will use it to have very clear leverage on the state of the listing.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is intended to run daily.

- The `premium_lens` table is intended to classify a property on what premium it is for its location. After analysis we arrive at a metric that takes into account the price and the price per m2.
- The `pricing_lens` table is intended to rank the listings according to the price published by the Seller. If this price is very different from what we estimated in the ForSale Calculator, we will classify as a different tier for those well priced.
- The `demand_lens` table is intended to classify a property in what demand . After analysis we arrive at a metric that takes into account the number of visits and the number of contacts.
- The `availability_lens` table is intended to classify a property in what availability. Takes elements into consideration: Key Location Score, Score of Hours Available for Weekly Visit, Score of Active Rental Contract and Score of Visit Cancelled due to Non-Authorization.
- The `listing_lenses` table is is where we unify all the other lens tables. Taking just the latest status for each sale listing, we create a table that will serve as the current status for all the sale listings.


More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following tables in enrich layer:

Via **Full Load**:
    - `availability_lens`
    - `demand_lens`
    - `listing_lenses`
    - `pricing_lens`
    - `sellability_lens`
    - `segmentation_bins`

</details>
