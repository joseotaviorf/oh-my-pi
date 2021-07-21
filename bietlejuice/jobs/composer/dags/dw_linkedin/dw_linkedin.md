## DW LinkedIn
### Important Note
This DAG was deactivated since Marketing team is not running any campaigns on LinkedIn, therefore no data is being generated.
In future, Marketing team may run new campaigns, so this DAG may need to be reactivated. If this is the case, add the dependencies removed in this PR (https://github.com/quintoandar/bi-etl-ejuice/pull/5195) to the `dependencies.yaml` file.

### Purpose
Creates incremental DW fact and dimension tables for LinkedIn campaigns to analyse ads costs retrieved from LinkedIn's API, using our own client integration available in [this API LinkeDin Criteo repository](https://github.com/quintoandar/linkedin-client-python)). LinkedIn Ads is a paid ads platform to display advertisements on LinkedIn social network.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
  
### Execution Interval
Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output tables in DW layer: 

- `linkedin.fact_linkedin_daily_cost_attributions`
- `linkedin.dim_linkedin_campaign`
- `linkedin.dim_linkedin_campaign_group`
- `linkedin.dim_linkedin_creative`

### Responsible Data Team
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>