## DW Marketing Costs LinkedIn
### Important Note
This DAG was deactivated since we don't need it for now.
In the future we may need to reactivate it. In this case,  add the dependencies removed in this PR
(https://github.com/quintoandar/bi-etl-ejuice/pull/5195) to the dependencies.yaml file.
### Purpose

LinkedIn Ads is a tool the Marketing team uses to serve ads to users across the LinkedIn platform. This DAG creates the facts and dims associated with this flow.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
  
### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there are the following output tables for both our staging and dw layers:

- `fact_linkedin_daily_cost_attributions`
- `dim_linkedin_campaign`
- `dim_linkedin_campaign_group`
- `dim_linkedin_creative`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>
