## Reverse Navent BigQuery

### Purpose

Navent is being responsible for some reports related to Benvi on Mexico, and as data flows through our products,
it's only accessible by QuintoAndar. This DAG builds tables based on our data lake/DW data and exports it to Navent's BigQuery.
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

On reverse's data lake layer, partitioning the DAG's execution date: 

- `benvi_contract_billing_enrichment`
- `benvi_monthly_bp_demand_metrics`
- `benvi_monthly_bp_supply_metrics`
- `benvi_weekly_bp_demand_metrics`

This pipeline exports the tables to Navent's BigQuery tables:
- `benvi_contract_billing_enrichment` is related to BigQuery's `benvi.mb_contracts`
- `benvi_monthly_bp_demand_metrics` is related to BigQuery's `benvi.monthly_bp_demand_metrics`
- `benvi_monthly_bp_supply_metrics` is related to BigQuery's `benvi.monthly_bp_supply_metrics`
- `benvi_weekly_bp_demand_metrics` is related to BigQuery's `benvi.weekly_bp_demand_metrics`

</details>
