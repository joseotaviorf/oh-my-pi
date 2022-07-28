## Enrich Brand Tracking
​
### Purpose
​
This DAG creates the enriched table of the first layer of enrichment from Media Plan DAG, by making a union of media plan historical data with current quarter data and applying some transformations to get the daily cost of each advertisement.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered quarterly.

More information about run time [here]({chart_url}{dag_id})

### Outputs
​
This pipeline produces the following output table: 
​
- `branding_media_plan_daily` – Contains the costs of each advertisement in a daily basis.
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>