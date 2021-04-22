## Enrich Consolidated Marketing Costs
### Purpose

This DAG is responsible for running the query that consolidates our marketing media data. This data is created from our media enrich layers. We will use this table in the Fact Marketing Daily Costs flow.

More information about the Fact's architecture can be found at [this diagram] (https://app.diagrams.net/#G1yUgcYdStBE-t916hcZAS8PWjiGwuvqbk) under the "New Arch" tab.

### Execution Interval

Daily after enrich layers. More information about run time [here]({chart_url}{dag_id}).

### Outputs

- `enrich_consolidated_marketing_costs.consolidated_google_costs`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).