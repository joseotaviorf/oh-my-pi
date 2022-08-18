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
    - `affiliate_pro_registration`
    - `base_supply_souce_for_rent`
    - `base_supply_souce_for_sale`
    - `branding_where_is_plaquinha`
    - `cities_neighborhoods_ibge_qa`
    - `costs_targets`
    - `ecglobal_active_users`
    - `historic_national_costs`
    - `indicaai_tax_costs`
    - `manual_cost_engagement_history`
    - `manual_cost_engagement`
    - `marketing_cost_taxonomy`
    - `mexico_costs_targets`
    - `mexico_demand_marketing_cost_per_source_actual`
    - `mexico_marketing_cost_per_source`
    - `mexico_supply_costs_financial_and_actual`
    - `mkt_cost_per_source`
    - `mta_budget`
    - `offline_manual_costs`
    - `offline_manual_share_city_group`
    - `offline_manual_share_cost_center`
    - `rental_tof_daily_targets`
    - `rental_tof_weekly_targets`
    - `taxonomy_affiliates`
    - `taxonomy_growth`
    - `tradecom_configuration`
    - `affiliates_extra_user_bonus`
    - `casa_mineira_marketing_cost_taxonomy`
    - `ciq_costs`
    - `city_share`
    - `local_holidays`
    - `plaquinhas_demand_targets`
    - `promotional_bonus_cluster_targets`
    - `promotional_bonus_user_cluster_targets`
    - `provisioned_costs_import`
    - `rental_flows_targets`
    - `rental_ntp_source_targets`
    - `sale_flows_targets`
    - `targets_casa_mineira_cost`
    - `targets_casa_mineira_ncp`
    - `targets_casa_mineira_tof_daily`
    - `targets_casa_mineira_tof_monthly`
    - `targets_casa_mineira_tof_weekly`
    - `targets_portal_casa_mineira`
    - `taxonomy_crm_casa_mineira`
    - `taxonomy_demand`
    - `taxonomy_portal_casa_mineira`
    - `tof_supply_targets`
    - `unit_economics_amortization_curve`
    - `week_volumes_supply`
    - `weekday_holiday_share`
    - `weekday_holiday_share_supply`
    - `weekday_supply_channel_share`
2. Data lake clean:
    - `affiliate_pro_registration`
    - `affiliates_cost_tradecom_configuration`
    - `affiliates_manual_cost_engagement_history`
    - `affiliates_manual_cost_engagement`
    - `affiliates_national_costs_history`
    - `branding_where_is_plaquinha`
    - `cities_neighborhoods_ibge_qa`
    - `costs_targets`
    - `daily_target_supply_rental`
    - `daily_target_supply_sale`
    - `ecglobal_active_users`
    - `indicaai_tax_costs`
    - `marketing_cost_taxonomy`
    - `mexico_costs_targets`
    - `mexico_demand_marketing_cost_per_source_actual`
    - `mexico_marketing_cost_per_source`
    - `mexico_supply_costs_financial_and_actual`
    - `mkt_cost_per_source`
    - `mta_budget_october_2020`
    - `offline_manual_costs`
    - `offline_manual_share_city_group`
    - `offline_manual_share_cost_center`
    - `rental_tof_daily_targets`
    - `rental_tof_weekly_targets`
    - `targets_casa_mineira_nbp`
    - `taxonomy_affiliates`
    - `taxonomy_growth`
    - `affiliates_extra_user_bonus`
    - `casa_mineira_marketing_cost_taxonomy`
    - `ciq_costs`
    - `city_share`
    - `local_holidays`
    - `plaquinhas_demand_targets`
    - `promotional_bonus_cluster_targets`
    - `promotional_bonus_user_cluster_targets`
    - `provisioned_costs_import`
    - `rental_flows_targets`
    - `rental_ntp_source_targets`
    - `sale_flows_targets`
    - `targets_casa_mineira_cost`
    - `targets_casa_mineira_ncp`
    - `targets_casa_mineira_tof_daily`
    - `targets_casa_mineira_tof_monthly`
    - `targets_casa_mineira_tof_weekly`
    - `targets_portal_casa_mineira_cost_cf`
    - `taxonomy_crm_casa_mineira`
    - `taxonomy_demand`
    - `taxonomy_portal_casa_mineira`
    - `tof_supply_targets`
    - `unit_economics_amortization_curve`
    - `week_volumes_supply`
    - `weekday_holiday_share`
    - `weekday_holiday_share_supply`
    - `weekday_supply_channel_share`
</details>
