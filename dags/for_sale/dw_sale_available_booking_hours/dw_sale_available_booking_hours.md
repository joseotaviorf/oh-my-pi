## DW Sale Available Booking Hours

### Purpose

This DAG uploads to the DW information related to the daily status of the amount of hours available for visits for each For Sale listing.  

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces in DW, schema sale, via incremental load:
    - `fact_daily_listing_available_hours`
​
​</details>