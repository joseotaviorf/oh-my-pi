## GSHEETS Growth Intra-Day

### Purpose

This DAG extracts data from Google Sheets files for Growth Context for sheets that are updated along the day, in a different time than the GSheets Growth DAG.

If you need information to understand how you can add your sheet, check our [Google Sheets Guide](https://www.notion.so/productquintoandar/Google-Sheets-0c11b1f13b7349918f91c0dec2b7e8f1).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables:

1. Data lake raw:
    - `casa_mineira_marketing_manual_shared_costs`
    - `marketing_costs_manual_shared_costs`
    - `marketing_costs_name_convention_shared_costs`
2. Data lake clean:
    - `casa_mineira_marketing_manual_shared_costs`
    - `marketing_costs_manual_shared_costs`
    - `marketing_costs_name_convention_shared_costs`

</details>
