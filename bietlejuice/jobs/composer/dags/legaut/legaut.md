## Legaut

### Purpose

This DAG imports the tables from Legaut database, a service used to track real state dillinges.


<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

In datalake raw and clean, via full load:
- `crawlers_crawler`
- `crawlers_crawlergroup`
- `crawlers_crawlertype`
- `meuSite_city`
- `meuSite_document`
- `meuSite_project`
- `meuSite_state`
- `meuSite_unit`

</details>
