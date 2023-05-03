## DW Sale Listings
​
### Purpose
​
This DAG creates the modelings for Sale Listings.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces in DW, schema Sale, via full load:
    - `dim_listing`
    - `fact_listings`
    - `fact_listing_status`
​
​</details>
