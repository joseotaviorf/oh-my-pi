## Enrich Braze Events Dispatches User
​
### Purpose
​
This DAG creates the incremental enriched tables for dispatches for both tenants and owners users from Braze.
​
### Execution​ Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables, on enrich layer: 
​
    - `owners_events`
    - `tenants_events` 
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​
