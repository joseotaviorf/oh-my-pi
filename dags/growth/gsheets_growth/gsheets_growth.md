## GSHEETS {dag_context}

### Purpose

This DAG extracts data from Google Sheets files for {dag_context} Context.

If you need information to understand how you can add your sheet, check our [Google Sheets Guide](https://www.notion.so/productquintoandar/Google-Sheets-0c11b1f13b7349918f91c0dec2b7e8f1).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is {trigger_interval} triggered.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables:

1. Data lake raw:
  {raw_tables}

2. Data lake clean:
  {clean_tables}

### Responsible Data Team

{additional_information}

### How to force run a gsheet

If you need to bypass the check for updated on a specific sheet, pass the following JSON to the DAG Config arguments, but change the example table names for the clean table name of your sheet:

```
{{'bypass_update_check_list':['events_aud','ciq_table']}}
```
</details>
