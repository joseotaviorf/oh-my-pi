## Metabase

### Purpose
This DAG imports the tables from [Metabase](https://github.com/quintoandar/deploy-metabase), our data visualization tool. 
We extract metadata from Metabase in order to analyze user behavior and have a better control of what is being created there.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces, in **datalake raw and clean**, tables via full and incremental load.

1. Via full load:
    - `collection`
    - `pulse_card`
    - `pulse_channel_recipient`
    - `query`
    - `query_execution`
    - `revision`
    - `view_log`

2. Via incremental load:
    - `core_user`
    - `metabase_database`
    - `metabase_field`
    - `metabase_table`
    - `pulse`
    - `pulse_channel`
    - `report_card`
    - `report_dashboard`
    - `report_dashboard_card`

### Responsible Data Engineering Team
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>