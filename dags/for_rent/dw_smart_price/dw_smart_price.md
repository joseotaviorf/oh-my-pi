## DW Smart Price
​
### Purpose
​
This DAG creates the modelings for Smart Price. The modelings integrate the Smart Price product into the listing and rental flows to better understand its performance and impact on the company.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces in DW, schema quintoandar, via full load:
    - `dim_smart_price`
    - `fact_listing_price_changes`
    - `fact_smart_price_status_changes` 
​