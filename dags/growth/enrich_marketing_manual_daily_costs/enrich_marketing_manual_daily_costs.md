## Enrich Marketing Automatic Daily Costs
### Purpose

This DAG generates the manual costs (i.e. gathered from gsheets tables) and saves its part in the final Fact Marketing Daily Costs aside Enrich Marketing Automatic Daily Costs.

More information about the Fact's architecture can be found at [this diagram] (https://app.diagrams.net/#G1aM-IGy6JcG1rxB0IyDxOJpyCU6GMoFzm) under the "New Arch" tab.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily after enrich layers. More information about run time [here]({chart_url}{dag_id}).

### Outputs

- `datalake_marketing_costs.daily_costs`

</details>
