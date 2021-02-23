## Enrich Braze Events User Centric Periodicity
​
### Purpose
​
This DAG creates the enriched tables for Braze user centric events by periodicity.
​
### Execution​ Interval
This DAG is triggered once per day via Mediator, after `enrich_braze_events_user_centric` DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces, via incremental load:

1. In datalake enrich:
    - `user_events_2w_ago` 
    - `user_events_3w_ago`
    - `user_events_all_time` 
    - `user_events_last_week`
    - `user_events_this_week`
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​
### Additional Information
​
The Data Analytics team responsible for Braze data is also on aforementioned document.
