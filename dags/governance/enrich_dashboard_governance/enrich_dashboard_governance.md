## Enrich Dashboard Governance

### Purpose

This Dag uses data extracted from Metabase to classify dashboards and charts.

<details>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Creates tables in schemas:

- `datalake_dashboard_governance`

The following tables are created incrementally:

- `chart_metadata`
- `dashboard_metadata`

</details>
