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
  * `datalake_casa_mineira_google_ads_raw.ads_performance`
  * `datalake_casa_mineira_google_ads_raw.keywords_performance`
  * `datalake_casa_mineira_google_ads_raw.campaigns_performance`
  * `datalake_casa_mineira_google_ads_raw.videos_performance`
* clean:
  * `datalake_casa_mineira_google_ads_clean.ads_performance`
  * `datalake_casa_mineira_google_ads_clean.keywords_performance`
  * `datalake_casa_mineira_google_ads_clean.campaigns_performance`
  * `datalake_casa_mineira_google_ads_clean.videos_performance`

</details>
