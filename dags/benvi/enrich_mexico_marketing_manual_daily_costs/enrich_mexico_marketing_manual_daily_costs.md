## Enrich Mexico Marketing Manual Daily Costs
### Purpose

This DAG generates the Benvi's Mexico operation manual costs (i.e. gathered from gsheets tables).

This is the [pipeline draw](https://www.figma.com/file/2FgsVbpgwtEmnn9RzbYZEU/Mexico-Marketing-Costs-Pipeline?node-id=0-1&t=L4OLMNfrjwCA3tfm-0]) related to the mexican marketing costs pipeline.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Notice that the used gsheet is loaded during the middle of the day, so this pipeline will only be available during the middle of the day.
More information about run time [here]({chart_url}{dag_id}).

### Outputs

- `datalake_mexico_marketing_costs.daily_costs`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data International team.
</details>