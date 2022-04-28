## GSHEETS GENERAL

### Purpose

This DAG extracts data from Google Sheets files for General/Cross Context.

If you need information to understand how you can add your sheet, check our [Google Sheets Guide](https://www.notion.so/productquintoandar/Google-Sheets-0c11b1f13b7349918f91c0dec2b7e8f1).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
  
### Execution Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables:

1. Data lake raw:
    - `carteira_ciq`
    - `events_aud`
    - `user_properties`
    - `tracking_catalog_projects`
2. Data lake clean:
    - `ciq_wallet`
    - `tracking_catalog_events_aud`
    - `tracking_catalog_user_properties`
    - `tracking_catalog_projects`

</details>
