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
    - `acquisition_target_per_source`
    - `affiliate_type_targets`
    - `affiliates_monthly_expected_results`
    - `agents_control`
    - `aux_agents_sale_hub`
    - `auxiliary_region`
    - `branding_where_is_plaquinha`
    - `census_subnormal_crowding_areas`
    - `ciq_costs`
    - `city_share`
    - `contact_type_taxonomy`
    - `contract_attribution_models`
    - `costs_allocation_relative_indexes`
    - `criteo_abtest_rj`
    - `crm_iptu_wave4`
    - `daily_target_supply_rental`
    - `daily_target_supply_sale`
    - `deduplicate_batch_listings_forsale`
    - `demand_channel_share`
    - `demand_retention_ab_tests`
    - `demand_targets_2019`
    - `demand_targets_2020`
    - `demand_targets_2021`
    - `demand_targets_replanning`
    - `department_control`
    - `department_schedule`
    - `entrance_inspection_csat`
    - `exit_inspection_csat`
    - `from_to_cancellation`
    - `google_searches_share_of_interest`    
    - `hotjar_photos_repressed_demand`
    - `hub_agents_hierarchy`      
    - `inspection_bugs`
    - `inspection_bugs_v2`
    - `inspectors_control`
    - `local_holidays`
    - `marketing_costs_campaign_city`
    - `marketing_costs_full_taxonomy`
    - `marketing_costs_google_ad_type_flags`
    - `marketing_costs_kenshoo_configuration`
    - `marketing_costs_manual_costs_google`
    - `marketing_costs_national_affiliate_historical_costs`
    - `marketing_kenshoo_configuration`
    - `marketing_manual_campaign_cities`
    - `marketing_manual_costs_google`
    - `marketing_social_media_costs`
    - `media_plan_current_quarter`
    - `mkt_cost_per_source`
    - `mta_budget_october_2020`
    - `offers_hub_central`
    - `offline_and_branding_marketing_costs`
    - `offline_manual_costs`
    - `offline_manual_share_city_group`
    - `offline_manual_share_cost_center`
    - `owner_entrance_inspection_csat`
    - `owner_exit_inspection_csat`
    - `payments_deals_and_discounts`
    - `poa_partners`
    - `process_eviction`
    - `projreparos_espelhamento_dl`
    - `promotional_bonus_cluster_targets`
    - `promotional_bonus_segmentation_targets`
    - `promotional_bonus_user_cluster_targets`
    - `promotional_bonus_user_targets`
    - `rent_criteo_eng_ab_test`
    - `rental_cohort_demand`
    - `rental_cohort_supply`
    - `rental_flows_targets`
    - `rental_ntp_source_targets`
    - `rental_rtp_targets`
    - `rental_tof_daily_targets`
    - `rental_tof_monthly_targets`
    - `rental_tof_weekly_targets`
    - `retention_exclusivity_active_contact`
    - `sale_criteo_eng_ab_test`
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
    - `survival_estimation_new_version`
    - `survival_estimation`
    - `targets_acquisition_cumulative_autonomous_agent`
    - `targets_agents_engagement`
    - `target_nps_weekly`
    - `target_sale_cohort_demand`
    - `target_sale_cohort_supply`
    - `targets_avg_ticket_adm_fee`
    - `targets_nr_bf_er_or`
    - `target_supply_and_demand_autonomous_agent`
    - `taxonomy_affiliates`
    - `taxonomy_demand`
    - `taxonomy_mkt_cost_new_test`
    - `taxonomy_mkt_cost`
    - `taxonomy_portal_casa_mineira`
    - `tenant_entrance_inspection_csat`
    - `users_cx_plaquinhas`
    - `weekday_demand_share`
    - `weekday_holiday_share`
    - `weekday_holiday_share_supply`
    - `weekday_supply_channel_share`
    - `week_volumes_demand`
    - `week_volumes_supply`

### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>
