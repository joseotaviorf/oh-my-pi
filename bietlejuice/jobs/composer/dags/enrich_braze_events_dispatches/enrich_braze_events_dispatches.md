## Enrich Braze Events Dispatches
​
### Purpose
​
This DAG creates the incremental enriched tables for dispatch events for both tenants and owners from Braze.
​
### Execution​ Interval
This DAG is triggered once per day via Mediator, after enrich_braze_events DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output table: 
​
- `email_owners` – Contains information about email dispatches for owners.
- `email_tenants` – Contains information about email dispatches for tenants.
- `sms_owners` – Contains information about SMS dispatches for owners.
- `sms_tenants` – Contains information about SMS dispatches for tenants.
- `inapp_owners` – Contains information about InApp dispatches for owners.
- `inapp_tenants` – Contains information about InApp dispatches for tenants.
- `push_owners` – Contains information about push dispatches for owners.
- `push_tenants` – Contains information about push dispatches for tenants.
- `webhook_owners` – Contains information about webhook dispatches for owners.
- `webhook_tenants` – Contains information about webhook dispatches for tenants.
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​
### Additional Information
​
The Data Analytics team responsible for Braze data is also on aforementioned document.
