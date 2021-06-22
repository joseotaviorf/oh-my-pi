## DW Tenant Booking Review
​
### Purpose
​
Full load of the context Tenant Booking Review model into DW with data from insider and ebdb.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
### Execution​ Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces in DW, schema public, via full load:
    - `dim_tenant_booking_review`
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​</details>