## DW Sale Listings
​
### Purpose
​
This DAG creates the modelings for Sale Listings.
​
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
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​