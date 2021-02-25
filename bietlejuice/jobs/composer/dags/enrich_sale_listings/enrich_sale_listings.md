## Enrich Sale Listings
​
### Purpose
​
This DAG creates the enriched tables for Sale Listings context.
​
### Execution​ Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following tables in enrich layer, via full load:
    - `sale_listings`
    - `sale_listings_status`
    - `sale_status_version_order`
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​