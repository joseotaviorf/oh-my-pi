## GSHEETS FOR RENT

### Purpose

This DAG extracts data from Google Sheets files for For Rent Context.

If you need information to understand how you can add your sheet, check our [Google Sheets Guide](https://www.notion.so/productquintoandar/Google-Sheets-0c11b1f13b7349918f91c0dec2b7e8f1).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
  
### Execution Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables:

1. Data lake raw:
    - `forecast_cohort_demanda`
    - `forecast_cohort_supply`
    - `forecast_diario_demanda`
    - `forecast_diario_supply`

2. Data lake clean:
    - `rental_forecast_cohort_demand`
    - `rental_forecast_cohort_supply`
    - `rental_forecast_daily_demand`
    - `rental_forecast_daily_supply`

</details>
