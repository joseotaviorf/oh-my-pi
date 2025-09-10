## Concierge Ranking Metrics

### Purpose

This DAG is responsible for calculating and loading concierge metrics into our Data Lake.

<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once a day.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG produces the following tables in enrich layer:

- `concierge_ranking_metrics`
- `user_search_profile_metrics`

</details>
