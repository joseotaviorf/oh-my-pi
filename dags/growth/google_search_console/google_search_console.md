# Google Search Console

## Purpose

Google Search Console DAG retrieves QuintoAndar's Google Web Search data metrics from Google Search Console platform.

- [Documentation](https://developers.google.com/webmaster-tools/v1/searchanalytics)
- [Aggregation types](https://support.google.com/webmasters/answer/7576553?visit_id=638090418915582448-722979880&rd=1#urlorsite)

Extracted metrics:

- Impressions: The number of times any URL from your site appeared in search results viewed by a user, not including paid Google  Ads search impressions.
- Clicks: The number of clicks on your website URLs from a Google Search results page, not including clicks on paid Google Ads search results.
- Average Position: The average ranking of your website URLs for the query or queries. For example, if your site's URL appeared at position 3 for one query and position 7 for another query, the average position would be 5 ((3+7)/2).
- CTR: Click-through rate, calculated as Clicks / Impressions * 100.
- Posimp: Position * Impressions.


List of URLs retrieved in this DAG currently:
- https://www.quintoandar.com.br
- https://proprietario.quintoandar.com.br
- https://meulugar.quintoandar.com.br
- https://conteudos.quintoandar.com.br

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

## Execution Interval

Daily (retrieves between D-7 and D-1 data). More information about run time [here]({chart_url}{dag_id}).

## Outputs

This pipeline produces the following output tables in each layer:

* raw:
  * `datalake_google_search_console_raw.report_by_date`
  * `datalake_google_search_console_raw.report_by_page`
  * `datalake_google_search_console_raw.report_by_query`
  * `datalake_google_search_console_raw.report_by_page_and_query`
  * `datalake_google_search_console_raw.report_by_query_summarized`

* clean:
  * `datalake_google_search_console_clean.report_by_date`
  * `datalake_google_search_console_clean.report_by_page`
  * `datalake_google_search_console_clean.report_by_query`
  * `datalake_google_search_console_clean.report_by_page_and_query`
  * `datalake_google_search_console_clean.report_by_query_summarized`

</details>
