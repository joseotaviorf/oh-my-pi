## SimilarWeb Daily Metrics

### Attention Point!!!
Do not clear raw tasks that have finished successfully. We have a limited number of API credits and these tasks run a high number of API requests.

### Purpose
Retrieves data from [SimilarWeb API](https://github.com/quintoandar/similarweb-api-client-python).

SimilarWeb is a platform that provides web analytics services and offers its users information on their clients' and competitors' web traffic and performance.

SimilarWeb Metrics extracted in this DAG:

1. Traffic
    - Visits `(desktop, mobile web and total)`
    - Pages per visit `(desktop, mobile web and total)`
    - Average visit duration `(desktop, mobile web and total)`
    - Bounce rate `(desktop, mobile web and total)`
    - Unique visitors `(desktop and mobile web)`

2. Traffic Sources
    - Visits `(desktop web)`
    - Pages per visit `(desktop web)`
    - Average visit duration `(desktop web)`
    - Bounce rate `(desktop web)`


<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
Weekly. More information about run time [here]({chart_url}{dag_id}).

### Outputs
We incrementally load the following tables into the datalake Raw and Clean:

- Raw
  - `datalake_similarweb_daily_metrics_raw.traffic`
  - `datalake_similarweb_daily_metrics_raw.traffic_sources`

- Clean
  - `datalake_similarweb_daily_metrics_clean.traffic`
  - `datalake_similarweb_daily_metrics_clean.traffic_sources`

</details>
