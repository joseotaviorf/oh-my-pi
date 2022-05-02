## GSHEETS STATIC

### Purpose

This DAG extracts data from static Google Sheets files (i.e., gsheets that don't have recurrent updates).

If you need information to understand how you can add your sheet, check our [Google Sheets Guide](https://www.notion.so/productquintoandar/Google-Sheets-0c11b1f13b7349918f91c0dec2b7e8f1).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG does not have an automatic trigger. It is run manually when necessary.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables:

1. Data lake raw:
    - `affiliates_acquisition_targets`
    - `autonomous_agent_listing`
    - `autonomous_agent_payment_data_form_origin`
    - `autonomous_agent_payment_data_lead_origin`
    - `aux_agents_sale`
    - `demand_targets_2019`
    - `demand_targets_replanning`
    - `costs_allocation_relative_indexes`
    - `dados_docato`
    - `demand_targets_2020`
    - `de_para_cancelamento`
    - `mra_historical`
    - `offline_and_branding_marketing_costs`
    - `rental_tof_daily_targets`
    - `supply_targets_2019`
    - `supply_targets_2020`
    - `supply_targets_2021`
    - `survival_estimation`
    - `survival_estimation_new_version`
    - `users_cx_plaquinhas`
2. Data lake clean:
    - `affiliates_acquisition_targets`
    - `autonomous_agent_listing`
    - `autonomous_agent_payment_data_form_origin`
    - `autonomous_agent_payment_data_lead_origin`
    - `aux_agents_sale`
    - `demand_targets_2019`
    - `demand_targets_2020`
    - `demand_targets_replanning`
    - `costs_allocation_relative_indexes`
    - `from_to_cancellation`
    - `legal_base_docato`
    - `mra_historical`
    - `offline_and_branding_marketing_costs`
    - `rental_tof_daily_targets`
    - `supply_targets_2019`
    - `supply_targets_2020`
    - `supply_targets_2021`
    - `survival_estimation`
    - `survival_estimation_new_version`
    - `users_cx_plaquinhas`

</details>
