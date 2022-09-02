# Google Search Console

## Purpose

Google Search Console DAG retrieves QuintoAndar's Google Web Search data metrics from Google Search Console platform.

Extracted metrics:

* Impressions: The number of times any URL from your site appeared in search results viewed by a user, not including paid Google  Ads search impressions.
* Clicks: The number of clicks on your website URLs from a Google Search results page, not including clicks on paid Google Ads search results.
* Average Position: The average ranking of your website URLs for the query or queries. For example, if your site's URL appeared at position 3 for one query and position 7 for another query, the average position would be 5 ((3+7)/2).
* CTR: Click-through rate, calculated as Clicks / Impressions * 100.

List of domains retrieved in this DAG currently:
* sc-domain:quintoandar.com.br

List of URLs retrieved in this DAG currently:
* https://www.quintoandar.com.br

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

## Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

## Outputs

This pipeline produces the following output tables in each layer:

* raw:
  * `datalake_google_search_console_raw.domain_by_property`
  * `datalake_google_search_console_raw.domain_by_page`
  * `datalake_google_search_console_raw.domain_by_property_without_query`
  * `datalake_google_search_console_raw.domain_by_page_without_page`
  * `datalake_google_search_console_raw.url_by_property`
  * `datalake_google_search_console_raw.url_by_page`
  * `datalake_google_search_console_raw.url_by_property_without_query`
  * `datalake_google_search_console_raw.url_by_page_without_page`
* clean:
  * `datalake_google_search_console_clean.domain_by_property`
  * `datalake_google_search_console_clean.domain_by_page`
  * `datalake_google_search_console_clean.domain_by_property_without_query`
  * `datalake_google_search_console_clean.domain_by_page_without_page`
  * `datalake_google_search_console_clean.url_by_property`
  * `datalake_google_search_console_clean.url_by_page`
  * `datalake_google_search_console_clean.url_by_property_without_query`
  * `datalake_google_search_console_clean.url_by_page_without_page`

## Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>
