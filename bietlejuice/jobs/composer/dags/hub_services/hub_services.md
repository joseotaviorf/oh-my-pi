## Hub Services

### Purpose
This DAG imports the tables from [HubServices](https://github.com/quintoandar/hubs), a service that centralizes hub data.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in datalake raw and clean:

Via **incremental load**:
    - `business_unit`
    - `business_unit_aud`
    - `lead`
    - `lead_aud`
    - `region`
    - `region_aud`
    - `rev_info`
    - `user_sample`
    - `user_sample_aud`
    - `visitor`
    - `visitor_aud`

### Responsible Data Teams
For any questions or concerns about this DAG and data, please contact the Data Engineering Team or
Data Analytics Team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>