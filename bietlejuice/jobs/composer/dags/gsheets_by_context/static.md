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
    - `autonomous_agent_payment_data_form_origin`
    - `autonomous_agent_payment_data_lead_origin`
    - `costs_allocation_relative_indexes`
    - `dados_docato`
    - `offline_and_branding_marketing_costs`
    - `rental_tof_daily_targets`
    - `supply_targets_2021`
    - `survival_estimation`
2. Data lake clean:
    - `autonomous_agent_payment_data_form_origin`
    - `autonomous_agent_payment_data_lead_origin`
    - `costs_allocation_relative_indexes`
    - `legal_base_docato`
    - `offline_and_branding_marketing_costs`
    - `rental_tof_daily_targets`
    - `supply_targets_2021`
    - `survival_estimation`

</details>
