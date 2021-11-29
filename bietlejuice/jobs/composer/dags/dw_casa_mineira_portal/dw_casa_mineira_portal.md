## DW Casa Mineira Portal
​
### Purpose
​
This DAG creates the DW modelings for Portal Casa Mineira.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces in DW, schema casa_mineira_portal, via full load:
    - `dim_house`
    - `dim_house_amenities`
    - `dim_house_feature`
    - `dim_real_estate_agency`
    - `fact_listing_flows`
    - `fact_listing_status`
    - `fact_ongoing_listing`
    - `fact_ongoing_real_estate_agency`
    - `fact_real_estate_budget_flows` 
    - `fact_real_estate_flow`
    - `fact_real_estate_status`
​
### Responsible Data Teams
​
For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​</details>
