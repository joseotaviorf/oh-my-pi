## GSHEETS
​
### Purpose
​
This DAG extracts data from Google Sheets files.

If you need information to understand how you can add your sheet, check our [Google Sheets Guide](https://www.notion.so/productquintoandar/Google-Sheets-0c11b1f13b7349918f91c0dec2b7e8f1).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
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
    - `ciq_costs`
    - `deduplicate_batch_listings_forsale`
    - `demand_channel_share`
    - `demand_targets_2019`
    - `demand_targets_2020`
    - `demand_targets_2021`
    - `entrance_inspection_csat`
    - `exit_inspection_csat`
    - `from_to_cancellation`
    - `hotjar_photos_repressed_demand`
    - `inspection_bugs`
    - `local_holidays`
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
    - `marketing_offline_budget`
    - `marketing_offline_manual_costs`
    - `marketing_offline_manual_share_city_group`
    - `marketing_offline_manual_share_cost_center`
    - `mkt_cost_per_source`
    - `owner_entrance_inspection_csat`
    - `owner_exit_inspection_csat`
    - `photos_recovery_common_area_facade`
    - `projreparos_espelhamento_dl`
    - `rental_cohort_demand`
    - `rental_cohort_supply`
    - `rental_flows_targets`
    - `rental_ntp_source_targets`
    - `rental_rtp_targets`
    - `rental_tof_daily_targets`
    - `rental_tof_monthly_targets`
    - `rental_tof_weekly_targets`
    - `sale_demand_targets`
    - `sale_flows_targets`
    - `sale_nbp_source_targets`
    - `sale_ongoing_listings_targets`
    - `sale_payment_concluded_targets`
    - `sale_rbp_targets`
    - `sale_supply_targets`
    - `sale_tof_daily_targets`
    - `sale_tof_monthly_targets`
    - `sale_tof_weekly_targets`
    - `supply_targets_2019`
    - `supply_targets_2020`
    - `supply_targets_2021`
    - `survival_estimation`
    - `survival_estimation_new_version`
    - `target_sale_cohort_demand`
    - `target_sale_cohort_supply`
    - `target_supply_and_demand_autonomous_agent`
    - `targets_acquisition_cumulative_autonomous_agent`
    - `targets_agents_engagement`
    - `targets_avg_ticket_adm_fee`
    - `targets_nr_bf_er_or`
    - `taxonomy_affiliates`
    - `taxonomy_demand`
    - `tenant_entrance_inspection_csat`
    - `week_volumes_demand`
    - `week_volumes_supply`
    - `weekday_demand_share`
    - `weekday_holiday_share`
    - `weekday_holiday_share_supply`
    - `weekday_supply_channel_share`

### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>