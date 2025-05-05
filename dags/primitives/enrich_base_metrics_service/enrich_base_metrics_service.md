## Enrich Base Metrics Service
### Purpose

This pipeline calculates the metrics for:
1. Analysis and monitoring.
2. Experimentation (AB Tests).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
### Execution Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer:
- `search_impressions`
- `recs_impressions`
- `global_metrics`
- `experiment_config`
- `experiment_config_processed`
- `house_publication_dates`
- `rent_flow_past_30_days`
- `sale_flow_past_30_days`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Search team in Data Products.

</details>
