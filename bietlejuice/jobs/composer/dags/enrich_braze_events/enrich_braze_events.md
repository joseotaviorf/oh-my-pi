## Enrich Braze Events
​
### Purpose
​
This DAG creates the enriched tables of the first layer of enrichment from Braze Events DAG, by cleaning data and applying an event type filter.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered daily, via Mediator.

More information about run time [here]({chart_url}{dag_id})

### Outputs
​
This pipeline produces the following output table: 
​
- `events_owners` – Contains information about events owners.
- `events_tenants` – Contains information about events tenants. 
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​
### Additional Information
​
If you need additional information about the Braze data, please contact Growth Data Analytics Team.  
​
### Major Changes (JIRA Tasks)
​
None.
</details>