## HubSpot

### Purpose
This DAG imports objects and pipeline information from HubSpot, a CRM service widely used in For Brokers.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in datalake_hubspot_raw and datalake_hubspot_clean:

Via **incremental load**:
    - `company`
    - `contact`
    - `deal`
    - `deal_pipeline`
    - `owner`
    - `team`
    - `ticket`
    - `ticket_pipeline`

### Responsible Data Teams
For any questions or concerns about this DAG and data, please contact the Data For Brokers Team.

</details>
