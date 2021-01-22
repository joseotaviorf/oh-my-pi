## Enrich Braze Events
​
### Purpose
​
This DAG creates the enriched tables events_owners and events_tenants, the first layer of enrichment from Braze Events DAG, by cleaning data and applying an event type filter.
​
### Execution​ Interval
This DAG is trigged once per day via Mediator.

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
For any questions or concerns about the DAG and its load, please contact the Data Integration Team.
​
### Additional Information
​
If you need additional information about the Braze data, please contact Growth Data Analytics Team.  
​
### Major Changes (JIRA Tasks)
​
None.