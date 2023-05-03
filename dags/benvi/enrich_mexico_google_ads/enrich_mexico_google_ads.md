# Enrich Mexico Google Ads

## Purpose

This DAG retrieves Benvi's mexican marketing campaigns data from Google Ads platform. It uses data extracted from [ads-performance](https://github.com/quintoandar/ads-performance) extraction tool, developed by Marketing Tools team.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

## Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

## Outputs

This pipeline produces the following output tables in each layer, via incremental load:

  * `datalake_mexico_google_ads.ads_performance`
  * `datalake_mexico_google_ads.campaigns_performance`
  * `datalake_mexico_google_ads.keywords_performance`
  * `datalake_mexico_google_ads.videos_performance`

</details>
