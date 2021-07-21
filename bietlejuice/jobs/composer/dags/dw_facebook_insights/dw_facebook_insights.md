## DW Facebook Insights
### Purpose

Creates incremental DW fact and dimension tables for Facebook campaigns to analyse ads costs retrieved from Facebook Insights's API, using our own client integration available in [this API Client Facbook repository](https://github.com/quintoandar/facebook-api-client-python)). Facebook Insights is a Facebook tool that provides a single, consistent interface to retrieve ad statistics. 

<details>
    <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered once per day via Mediator, after `bietlejuice.facebook_insights` DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output tables in DW layer: 

- `facebook_insights.fact_facebook_daily_cost_attributions`
- `facebook_insights.dim_facebook_ad`
- `facebook_insights.fact_facebook_social_costs`
- `facebook_insights.dim_facebook_social_costs`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>