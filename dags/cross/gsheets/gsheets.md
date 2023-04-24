## GSHEETS

### Purpose

This DAG extracts data from Google Sheets files.

If you need information to understand how you can add your sheet, check our [Google Sheets Guide](https://www.notion.so/productquintoandar/Google-Sheets-0c11b1f13b7349918f91c0dec2b7e8f1).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables:

1. Data lake raw:
    - All gsheets defined in `gsheets_files.yaml`

2. Data lake clean:
    - `affiliate_type_targets`
    - `affiliates_extra_user_bonus`
    - `affiliates_inactive_segmentation`
    - `affiliates_monthly_expected_results`
    - `agents_control`
    - `agents_ranking_targets`
    - `agreements_discounts_answer_forms`
    - `bbb22_coupon_sale_users`
    - `bbb22_giveaway_rent_users`
    - `braze_campaign_creative`
    - `braze_canvas_creative`
    - `casa_mineira_inside_sales_pipe`
    - `casa_mineira_marketing_cost_taxonomy`
    - `casa_mineira_marketing_manual_shared_costs`
    - `ciq_costs`
    - `city_share`
    - `contract_attribution_models`
    - `criteo_abtest_rj`
    - `crm_iptu_wave4`
    - `demand_channel_share`
    - `demand_targets_replanning`
    - `department_control`
    - `extra_invoice_created_expenses`
    - `from_to_cancellation`
    - `google_searches_share_of_interest`
    - `households_per_city_ibge`
    - `inside_sale_supply_targets`
    - `ipsos_brandtracking_questions`
    - `local_holidays`
    - `marketshare_units_and_tenants`
    - `marketshare_seasonality`
    - `media_plan_current_quarter`
    - `offline_manual_costs`
    - `offline_manual_share_city_group`
    - `offline_manual_share_cost_center`
    - `owner_offboarding_repair_csat`
    - `promotional_bonus_cluster_targets`
    - `promotional_bonus_segmentation_targets`
    - `promotional_bonus_user_cluster_targets`
    - `promotional_bonus_user_targets`
    - `provisioned_costs_import`
    - `rent_criteo_eng_ab_test`
    - `rental_flows_targets`
    - `rental_ntp_source_targets`
    - `sale_criteo_eng_ab_test`
    - `sale_flows_targets`
    - `sale_rbp_targets`
    - `targets_acquisition_cumulative_autonomous_agent`
    - `targets_agents_engagement`
    - `targets_casa_mineira_cost`
    - `targets_casa_mineira_ncp`
    - `targets_casa_mineira_tof_daily`
    - `targets_casa_mineira_tof_monthly`
    - `targets_casa_mineira_tof_weekly`
    - `targets_portal_casa_mineira_cost_cf`
    - `target_supply_and_demand_autonomous_agent`
    - `taxonomy_crm_casa_mineira`
    - `taxonomy_mkt_cost`
    - `taxonomy_portal_casa_mineira`
    - `tof_supply_targets`
    - `tracking_catalog_event_properties`
    - `tv_ads`
    - `unit_economics_amortization_curve`
    - `weekday_demand_share`
    - `week_volumes_demand`
    - `week_volumes_supply`
    - `weekday_holiday_share`
    - `weekday_holiday_share_supply`
    - `weekday_supply_channel_share`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>
