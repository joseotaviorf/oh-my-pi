## Find Health Metrics

### Purpose

This pipeline processes health metrics relevant to Concierge.

<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once a day.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer: 

- `concierge_messages`
- `concierge_direct_vb`
- `concierge_indirect_vb`
- `concierge_prospects_aux`
- `concierge_demand`

</details>
