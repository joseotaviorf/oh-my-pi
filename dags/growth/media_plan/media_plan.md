## Media Plan

### Purpose

This DAG creates the incremental table for Media Plan. Media Plan data is related to QuintoAndar's campaigns/advertisements with the aim of increasing brand relevance. Most of them are published on offline channels (TV, radio, outdoor, etc).

The table contains historical data, once is related to campaigns/advertisements that really happened, in contrast to data in table datalake_gsheets_clean.media_plan_current_quarter, which are related to campaigns/advertisements that are planned to happen.

The Data Analysts of Mkt Branding upload the file quarterly at this s3 bucket path: 5a-datalake-prod/raw/files/mkt_branding/media_plan/

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered quarterly.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

1. In datalake raw:
    - `datalake_media_plan_raw.media_plan`
    

2. In datalake clean:
    - `datalake_media_plan_clean.media_plan`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
  
</details>