## Casa Mineira Google Ads

### Purpose

Casa Mineira Google Ads DAG retrieves Casa Mineira's marketing campaigns data from Google Ads platform. It uses data extracted from [ads-performance](https://github.com/quintoandar/ads-performance) extraction tool, developed by Marketing Tools team.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables in each layer:
* raw:
    - `datalake_casa_mineira_google_ads_raw.ads_performance_report`
    - `datalake_casa_mineira_google_ads_raw.keywords_performance_report`
    - `datalake_casa_mineira_google_ads_raw.campaigns_performance_report`
    - `datalake_casa_mineira_google_ads_raw.videos_performance_report`
* clean:
    - `datalake_casa_mineira_google_ads_clean.ads_performance_report`
    - `datalake_casa_mineira_google_ads_clean.keywords_performance_report`
    - `datalake_casa_mineira_google_ads_clean.campaigns_performance_report`
    - `datalake_casa_mineira_google_ads_clean.videos_performance_report`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>
