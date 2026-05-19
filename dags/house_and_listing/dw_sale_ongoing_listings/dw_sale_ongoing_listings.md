## DW Sale Ongoing Listings
### Purpose

This DAG uploads to the DW a periodic snapshot table about ForSale ongoing listings.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces in DW, schema sale, via full load:
    - `fact_daily_ongoing_listing`
​
​</details>