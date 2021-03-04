## Enrich Consolidated Google Costs
### Purpose

This DAG is responsible for running the query that consolidates our historical Google data. This data is created from our current DW data mixed with data from our historical national affiliates spreadsheet. We will use this table in our Fact Marketing Daily Costs flow, where we will consolidate all of our affiliate costs (including Google) into one.

More information about the Fact's architecture can be found at [this diagram] (https://app.diagrams.net/#G1yUgcYdStBE-t916hcZAS8PWjiGwuvqbk) under the "New Arch" tab.

### Execution Interval

Monthly (historical data might change). More information about run time [here]({chart_url}{dag_id}).

### Outputs

`enrich_consolidated_marketing_costs.consolidated_google_costs`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
