## DW Criteo Campaings
### Purpose

Creates incremental DW fact and dimension tables for Criteo campaigns to analyse retargeting costs retrieved from Criteo's API, using our own client integration available in [this API Client Criteo repository](https://github.com/quintoandar/criteo-api-client-python)). Criteo is a retargeting platform - serves ads based on people that have already visited our site - used to show ads to our clients.

<details>
    <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered once per day via Mediator, after `bietlejuice.criteo_campaigns` DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output tables in DW layer: 
​
- `criteo_campaigns.dim_criteo_campaign`
- `criteo_campaigns.fact_criteo_daily_cost_attributions` 
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>