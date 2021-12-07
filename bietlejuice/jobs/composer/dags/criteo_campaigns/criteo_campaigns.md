## Criteo Campaigns

### Purpose

Criteo Campaigns DAG retrieves Quinto Andar's marketing campaign statistics from Criteo platform. It uses data extracted from [Criteo API Analytics endpoint](https://developers.criteo.com/marketing-solutions/reference/analytics-1) using [Quinto Andar's Criteo API Client](https://github.com/quintoandar/criteo-api-client-python), with credentials from [DataEng App](https://partners.criteo.com/dashboard/1706/apps/1841).
Criteo is a retargeting platform - serves ads based on people that have already visited our site - used to show ads to our clients.
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, via incremental load:

- In datalake raw:
    - `datalake_criteo_campaigns_raw.criteo_campaigns`
- In datalake clean:
    - `datalake_criteo_campaigns_clean.criteo_campaigns`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>
