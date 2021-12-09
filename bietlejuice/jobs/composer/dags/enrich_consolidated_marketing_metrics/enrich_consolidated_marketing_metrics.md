## Enrich Consolidated Marketing Metrics
### Purpose

Consolidated Marketing Metrics DAG groups marketing metrics for QuintoAndar's media channels.

#### Structure

Each media has a consolidated table, which aggregates metrics. All consolidated tables are united in the `consolidated_media_metrics` query, where **city groups** and **sharing rules** are applied.

For Google Ads consolidation, most of data is present in multiple Google reports, so a deduplication occurs, selecting which report is used to retrieve each distinct combination of `campaign` + `ad_group_name`, according to the following priority sequence of reports:

1. VIDEO_PERFORMANCE_REPORT
2. KEYWORDS_PERFORMANCE_REPORT
3. AD_PERFORMANCE_REPORT
4. CAMPAIGN_PERFORMANCE_REPORT

Report type names are based in this [Google Ads API doc](https://developers.google.com/adwords/api/docs/appendix/reports), **and must be the same used in taxonomy mappings**.

More information about marketing data flow architecture can be found at [this diagram](https://viewer.diagrams.net/?page-id=XMpkxgjBueLUIo4w7sMd&highlight=0000ff&nav=1&hide-pages=1#G1aM-IGy6JcG1rxB0IyDxOJpyCU6GMoFzm), also shown in details below.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
  <iframe
    src="https://viewer.diagrams.net/?page-id=XMpkxgjBueLUIo4w7sMd&highlight=0000ff&nav=1&hide-pages=1#G1aM-IGy6JcG1rxB0IyDxOJpyCU6GMoFzm"
    style="width:100%; height:300px;">
  </iframe>

### Execution Interval

Daily after enrich layers. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, via incremental load:

- In datalake's `enrich` layer:
    - `datalake_consolidated_marketing_metrics.consolidated_media_metrics`
    - `datalake_consolidated_marketing_metrics.criteo_consolidated_metrics`
    - `datalake_consolidated_marketing_metrics.facebook_consolidated_metrics`
    - `datalake_consolidated_marketing_metrics.google_consolidated_metrics`
    - `datalake_consolidated_marketing_metrics.mitula_consolidated_metrics`
    - `datalake_consolidated_marketing_metrics.rtb_consolidated_metrics`
    - `datalake_consolidated_marketing_metrics.trovit_consolidated_metrics`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>