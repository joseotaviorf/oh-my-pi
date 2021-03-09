## DW Marketing Costs

### Purpose

This DAG creates the dim and fact that the Marketing Analysts will use to analyze cost information for our marketing costs (GOOGLE ONLY). In addition, these tables will be used to create our main marketing table, `fact_marketing_daily_costs`

### Execution Interval
This dag is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id})

### Outputs

This pipeline produces the following output tables in both our staging and dw layers:

- `dw_marketing.fact_google_daily_cost_attributions`
- `dim_google_ad`
- `dim_google_campaign`
- `dim_google_keyword`
- `dim_google_video`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
