## DW Sale Listing Price Changes

### Purpose

This DAG uploads to the DW information related to changes in the sales price of a listing over time, as well as the calculator price tied to that change.  

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces in DW, schema sale, via full load:
    - `fact_listing_price_changes`
​
​</details>