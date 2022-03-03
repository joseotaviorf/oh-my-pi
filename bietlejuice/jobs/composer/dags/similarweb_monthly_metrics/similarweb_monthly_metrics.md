## SimilarWeb Monthly Metrics
### Purpose
Retrieves data from [SimilarWeb API](https://github.com/quintoandar/similarweb-api-client-python).

SimilarWeb is a platform that provides web analytics services and offers its users information on their clients' and competitors' web traffic and performance.

SimilarWeb Metrics extracted in this DAG:

1. Traffic
    - Desktop vs Mobile Split

2. Traffic Sources
    - Visits `(desktop web and mobile web)`
    - Traffic Share `(desktop web)`


<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
Monthly. More information about run time [here]({chart_url}{dag_id}).

### Outputs
We incrementally load the following tables into the datalake Raw and Clean:

- Raw
  - `datalake_similarweb_monthly_metrics_raw.traffic`
  - `datalake_similarweb_monthly_metrics_raw.traffic_sources`

- Clean
  - `datalake_similarweb_monthly_metrics_clean.traffic`
  - `datalake_similarweb_monthly_metrics_clean.traffic_sources`

</details>
