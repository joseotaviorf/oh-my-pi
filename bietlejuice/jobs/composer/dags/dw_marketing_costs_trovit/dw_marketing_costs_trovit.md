## DW Marketing Costs Trovit
​
### Purpose
​
This DAG creates the incremental dw tables for Trovit campaigns, used to verify ads costs.
​
### Execution​ Interval
This DAG is triggered once per day via Mediator, after trovit DAG.


### Outputs
​
This pipeline produces the following output table: 
​
- `dim_trovit_campaign`
- `fact_trovit_daily_cost_attributions` 
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
