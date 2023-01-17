## Enrich Mexico Braze Details
​
### Purpose
​
This DAG creates the incremental enriched table from Braze Details clean tables,
by incrementally filtering only what is related to Mexico operation.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator, after enrich_braze_details DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output table: 
​
- `campaign_details_owners`
- `campaign_details_refiere_y_gana`
- `campaign_details_tenants`
- `canvas_details_owners`
- `canvas_details_refiere_y_gana`
- `canvas_details_tenants`


### Responsible Data Teams
​
For any questions or concerns about this DAG, please contact the DAG owner.
