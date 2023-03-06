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
    - `call`
    - `company`
    - `communication`
    - `contact`
    - `deal`
    - `deal_pipeline`
    - `email`
    - `marketing_campaign`
    - `marketing_email`
    - `marketing_email_event`
    - `meeting`
    - `note`
    - `owner`
    - `task`
    - `team`
    - `ticket`
    - `ticket_pipeline`

</details>
