## Enrich Recommendations
### Purpose

All recommendations delivered to users through different channels such as
daily feed/favorite houses email campaigns and similar houses carousel are
processed and enriched by this pipeline.

Then this pipeline calculates the metrics used to monitor online recommendations.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
### Execution Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer:

- `recommendation_catalog`
- `embeddings`
- `item_interaction`
- `recommendation`
- `recommendation_flow`
- `recommendation_features`
- `coverage`
- `diversity`
- `popularity`
- `recommendation_metrics_agg_recset`
- `recommendation_metrics_agg_dimensions`
- `recommendation_metrics_agg_display_type_business_context`
- `recommendation_metrics_agg_display_type_business_context_experiment`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Recommendations team in Data Products.

</details>
