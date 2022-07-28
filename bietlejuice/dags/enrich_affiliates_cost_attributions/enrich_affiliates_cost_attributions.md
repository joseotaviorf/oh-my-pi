## Enrich Affiliates Cost Attributions

### Purpose

Affiliates Cost Attributions DAG pivots QuintoAndar's EBDB affiliate engagement commission costs, also adding manual data and history data into it.

History data is retrieved from the table:

- `datalake_gsheets_clean.affiliates_manual_cost_engagement_history`

Custom manual data is retrieved from the table:

- `datalake_gsheets_clean.affiliates_manual_cost_engagement`

Commission rate values applied onto commission costs are retrived from the table:

- `datalake_gsheets_clean.affiliates_cost_tradecom_configuration`

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table via full load:

**enrich**:

- `datalake_affiliates_cost_attributions.affiliates_cost_attributions`
