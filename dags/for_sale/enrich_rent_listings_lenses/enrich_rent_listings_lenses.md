## Enrich Rent Listings Lenses

### Purpose

The purpose of this DAG is to materialize the analysis made by the Supply team. With it, we will create some tiers where we will classify the listings. We will use it to have very clear leverage on the state of the listing.
This DAG is analogous to the existing enrich_sale_listings_lenses from Sale.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We incrementally load the following tables into the Datalake:

- `listing_quality_lens`

</details>
