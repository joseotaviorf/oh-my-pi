## Enrich Google Search Console
### Purpose
This DAG generates tables to track demand user behaviors in the Google Search Console SEO funnel. It is relevant for the SEO tribe to monitor and analyze the results by page type so that the squads (transactional and informational) can more efficiently identify problems, impacts, and opportunities. In addition, this funnel helps to prioritize the most relevant pages for the business.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily (retrieves between D-7 and D-1 data). More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there are the following output tables in our enrich layer:

- `datalake_google_search_console.seo_gsc_data`

</details>
