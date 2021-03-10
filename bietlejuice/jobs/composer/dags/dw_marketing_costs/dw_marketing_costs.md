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

### Static Tables

This pipeline uses static tables brought from our old flow to save our history. They are:

- `fact_marketing_daily_costs_old`

Also, there are other historic tables in our datalake which are:

- `fact_google_daily_cost_attributions_old`
- `dim_google_ad_old`
- `dim_google_campaign_old`
- `dim_google_keyword_old`

\**There are more tables in redshift to improve our performance in queries. These tables are the source `fact_marketing_daily_costs_old` table filtered respectively by media (facebook and google costs*):

- `marketing_costs.fact_marketing_daily_costs_old_facebook`
- `marketing_costs.fact_marketing_daily_costs_old_google`

Gut Campaigns were reprocessed after a year, we could not put this old values in the old tables because some id columns used deprecated methods, so we created new tables for this campaigns:

- `fact_google_daily_cost_attributions_gut`
- `dim_google_ad_gut`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
