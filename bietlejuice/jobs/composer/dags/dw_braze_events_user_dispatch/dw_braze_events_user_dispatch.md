## DW Braze Events User Dispatch
​
### Purpose
​
This DAG creates the incremental modelings for Braze Events, context User Dispatch. 
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces in DW, schema `braze`, via incremental load:
    - `fact_braze_campaign_user_dispatch`
    - `fact_braze_canvas_user_dispatch`
​
### Responsible Data Teams
​
For any questions or concerns about this DAG, please contact the Data Engineering Team or Data Analytics Team
responsibles listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​</details>