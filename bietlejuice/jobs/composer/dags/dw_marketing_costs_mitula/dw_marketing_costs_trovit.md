## DW Marketing Costs Mitula
​
### Purpose
​
This DAG creates the incremental dw tables for Mitula campaigns, used to verify ads costs.
​
### Execution​ Interval
This DAG is triggered once per day via Mediator, after Mitula DAG.


### Outputs
​
This pipeline produces the following output table: 
​
- `dim_mitula_campaign`
- `fact_mitula_daily_cost_attributions` 
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
