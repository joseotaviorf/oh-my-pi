## Enrich Mexico Marketing Automatic Daily Costs
### Purpose

This DAG generates the Benvi's Mexico operation automatic costs (i.e. gathered from medias API/Crawlers) combined with the taxonomy tables and saves its part in the final Fact Marketing Daily Costs aside Enrich Mexico Marketing Manual Daily Costs.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily after enrich layers. More information about run time [here]({chart_url}{dag_id}).

### Outputs
This DAG creates, via incremental load:

- `datalake_mexico_marketing_costs.daily_costs`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data International team.

</details>