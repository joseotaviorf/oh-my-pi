## GSHEETS FOR SALE

### Purpose

This DAG extracts data from Google Sheets files for For Sale Context.

If you need information to understand how you can add your sheet, check our [Google Sheets Guide](https://www.notion.so/productquintoandar/Google-Sheets-0c11b1f13b7349918f91c0dec2b7e8f1).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
  
### Execution Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables:

1. Data lake raw:
    - `sale_asp_form_responses_2022q1`
    - `sale_asp_form_responses_2022q2`
    - `sale_asp_tratatives_2022q1`
    - `sale_asp_tratatives_2022q2_newlistings`
    - `sale_asp_tratatives_2022q2_oldlistings`
    - `sale_asp_groupsab_2022q2`
    - `sale_demand_targets`
    - `sale_ongoing_listings_targets`
    - `sale_payment_concluded_targets`
    - `sale_payments_tiers`
    - `sale_supply_targets`
    - `sale_tof_daily_targets`
    - `sale_tof_monthly_targets`
    - `sale_tof_weekly_targets`
    - `target_sale_cohort_demand`
    - `target_sale_cohort_supply`
2. Data lake clean:
    - `sale_asp_form_responses_2022q1`
    - `sale_asp_form_responses_2022q2`
    - `sale_asp_tratatives_2022q1`
    - `sale_asp_tratatives_2022q2_newlistings`
    - `sale_asp_tratatives_2022q2_oldlistings`
    - `sale_asp_groupsab_2022q2`
    - `sale_demand_targets`
    - `sale_ongoing_listings_targets`
    - `sale_payment_concluded_targets`
    - `sale_payments_tiers`
    - `sale_supply_targets`
    - `sale_tof_daily_targets`
    - `sale_tof_monthly_targets`
    - `sale_tof_weekly_targets`
    - `target_sale_cohort_demand`
    - `target_sale_cohort_supply`

</details>
