## Enrich Braze Events User Centric
​
### Purpose
​
This DAG creates the incremental enriched table for Braze user centric events with every campaign/canvas groupped daily. 
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator, after enrich_braze_events DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output table: 
​
- `user_events_daily` – Contains information about events of all types of Braze users.
​
### Responsible Data Teams
​
For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​</details>
