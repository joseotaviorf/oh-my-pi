## DW Braze Events User Centric
​
### Purpose
​
This DAG creates the incremental models for Braze Events of user centered data. It's a periodic snapshot fact that joins snapshots of 5 different time windows (`all time`, `last week`, `this week`, `2 weeks ago` and `3 weeks ago`) each one stored in a distinct table. Their data is joined by their execution date, which takes the role as a snapshot date. The information is summarized in one single fact for easy comparison.
​
### Execution​ Interval
This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces in DW, schema quintoandar, via incremental load:
    - `fact_braze_user_centric`
​
### Responsible Data Teams
​
For any questions or concerns about this DAG, please contact the Data Engineering Team or Data Analytics Team
responsibles listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​
