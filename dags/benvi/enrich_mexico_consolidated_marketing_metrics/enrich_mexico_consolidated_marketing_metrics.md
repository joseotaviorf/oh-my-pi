## Enrich Mexico Consolidated Marketing Metrics
### Purpose

Mexico Consolidated Marketing Metrics DAG groups marketing metrics for QuintoAndar's media channels related to Benvi operation. All consolidated tables are united in the `consolidated_media_metrics` query.

### Execution Interval

Daily after enrich layers. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, via incremental load:

- In datalake's `enrich` layer:
    - `datalake_mexico_consolidated_marketing_metrics.consolidated_media_metrics`
    - `datalake_mexico_consolidated_marketing_metrics.facebook_consolidated_metrics`
    - `datalake_mexico_consolidated_marketing_metrics.google_consolidated_metrics`
    - `datalake_mexico_consolidated_marketing_metrics.mitula_consolidated_metrics`
    - `datalake_mexico_consolidated_marketing_metrics.trovit_consolidated_metrics`