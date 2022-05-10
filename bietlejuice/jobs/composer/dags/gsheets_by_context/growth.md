## GSHEETS Growth

### Purpose

This DAG extracts data from Google Sheets files for Growth Context.

If you need information to understand how you can add your sheet, check our [Google Sheets Guide](https://www.notion.so/productquintoandar/Google-Sheets-0c11b1f13b7349918f91c0dec2b7e8f1).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables:

1. Data lake raw:
    - `branding_where_is_plaquinha`
    - `costs_targets`
    - `historic_national_costs`
    - `manual_cost_engagement`
    - `manual_cost_engagement_history`
    - `affiliate_pro_registration`
    - `historic_national_costs`
    - `manual_cost_engagement`
    - `manual_cost_engagement_history`
    - `offline_manual_costs`
    - `offline_manual_share_city_group`
    - `offline_manual_share_cost_center`
    - `mta_budget`
    - `tradecom_configuration`
2. Data lake clean:
    - `affiliate_pro_registration`
    - `affiliates_national_costs_history`
    - `affiliates_manual_cost_engagement`
    - `affiliates_manual_cost_engagement_history`
    - `affiliates_cost_tradecom_configuration`
    - `branding_where_is_plaquinha`
    - `costs_targets`
    - `offline_manual_costs`
    - `offline_manual_share_city_group`
    - `offline_manual_share_cost_center`
    - `targets_casa_mineira_nbp`
    - `mta_budget_october_2020`

</details>
