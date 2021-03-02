## GSHEETS
​
### Purpose
​
This DAG extracts data from Google Sheets files.
​
### Execution​ Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables:

1. Data lake raw:
    - All gsheets defined in `gsheets_files.yaml`

2. Data lake clean:
    - `auxiliary_region`
    - `from_to_cancellation`
    - `marketing_costs_affiliates_historic_national_costs`
    - `marketing_costs_campaign_city`
    - `marketing_costs_full_taxonomy`
    - `marketing_costs_google_ad_type_flags`
    - `marketing_costs_kenshoo_configuration`
    - `marketing_costs_manual_costs_google`
    - `marketing_costs_manual_shared_costs`
    - `marketing_costs_name_convention_shared_costs`
    - `marketing_manual_costs_google`
    - `reorganize_leads`
    - `taxonomy_demand`
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).