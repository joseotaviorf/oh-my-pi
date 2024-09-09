## Enrich Search
### Purpose


1. This pipeline calculates the metrics for search analysis and monitoring.
2. This pipeline calculates the metrics for search experimentation (AB Tests).
3This pipeline calculates the target used to monitor online search.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
### Execution Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer:
- `amplitude_user_device`
- `item_interaction`
- `item_interaction_sale`
- `search_impressions`
- `houses_published`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Search team in Data Products.

</details>
