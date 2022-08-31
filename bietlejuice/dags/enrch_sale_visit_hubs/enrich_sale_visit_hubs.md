## Enrich Sale Visit Hubs

### Purpose

Creates the enriched tables for the context `sale_visit_hubs` enriched from Teams, EBDB and gsheets.
The intention is to follow the business units that the agent is part of at the time of the visit, considering teams as the main source.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
  
### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, via full load:

- `sale_visit_hubs`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>