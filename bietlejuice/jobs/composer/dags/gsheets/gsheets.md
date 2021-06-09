## GSHEETS
​
### Purpose
​
This DAG extracts data from Google Sheets files.

If you need information to understand how you can add your sheet, check our [Google Sheets Guide](https://www.notion.so/productquintoandar/Google-Sheets-0c11b1f13b7349918f91c0dec2b7e8f1).
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
    - `census_subnormal_crowding_areas`
    - `entrance_inspection_csat`
    - `exit_inspection_csat`
    - `from_to_cancellation`
    - `hotjar_photos_repressed_demand`
    - `inspection_bugs`
    - `marketing_costs_campaign_city`
    - `marketing_costs_full_taxonomy`
    - `marketing_costs_google_ad_type_flags`
    - `marketing_manual_campaign_cities`
    - `marketing_costs_kenshoo_configuration`
    - `marketing_costs_manual_costs_google`
    - `marketing_costs_manual_shared_costs`
    - `marketing_costs_name_convention_shared_costs`
    - `marketing_costs_national_affiliate_historical_costs`
    - `marketing_manual_costs_google`
    - `marketing_offline_manual_costs`
    - `marketing_offline_manual_share_city_group`
    - `marketing_offline_manual_share_cost_center`
    - `owner_entrance_inspection_csat`
    - `owner_exit_inspection_csat`
    - `targets_avg_ticket_adm_fee`
    - `targets_nr_bf_er_or`
    - `taxonomy_affiliates`
    - `taxonomy_demand`
    - `tenant_entrance_inspection_csat`
    - `marketing_offline_budget`

### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).