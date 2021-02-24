## DW Smart Price
​
### Purpose
​
This DAG creates the modelings for Smart Price. The modelings integrate the Smart Price product into the listing and rental flows to better understand its performance and impact on the company.
​
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
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​
### Additional Information
​
The Data Analytics team responsible for Braze data is also on aforementioned document.
