## GSHEETS GROWTH

### Purpose

This DAG extracts data from Google Sheets files for Growth Context.

If you need information to understand how you can add your sheet, check our [Google Sheets Guide](https://www.notion.so/productquintoandar/Google-Sheets-0c11b1f13b7349918f91c0dec2b7e8f1).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
  
### Execution Interval

This DAG does not have an automatic trigger. It is run manually when necessary.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables:

1. Data lake raw:
    - `historic_national_costs`
    - `manual_cost_engagement`
    - `manual_cost_engagement_history`
    - `offline_manual_costs`
    - `offline_manual_share_city_group`
    - `offline_manual_share_cost_center`
    - `tradecom_configuration`
2. Data lake clean:
    - `affiliates_national_costs_history`
    - `affiliates_manual_cost_engagement`
    - `affiliates_manual_cost_engagement_history`
    - `affiliates_cost_tradecom_configuration`
    - `offline_manual_costs`
    - `offline_manual_share_city_group`
    - `offline_manual_share_cost_center`

</details>
