## Enrich Amplitude Partner Taxonomy
​
### Purpose
​
This DAG creates the enriched table amplitude_partner_taxonomy, which we will use to add a taxonomy to our Dim partner table. This table contains events data from the event type "register_form_completed".

### Execution​ Interval
This DAG is dependent on our `amplitude_events` DAG, and therefore is trigged via mediator after it is completed.

More information about run time [here]({chart_url}{dag_id})

### Outputs
​
This pipeline produces the following output table: 
​
- `amplitude_partner_taxonomy` – Contains UTM information about certain events.
​
### Responsible Data Engineering Team
​
For any questions or concerns about the DAG and its load, please contact the Data Marketing Team.
​
### Additional Information
​
If you need additional information about Amplitude or taxonomy,, please contact the Data Marketing Analytics Team.  
​
### Major Changes (JIRA Tasks)
​
[DTM-635](https://quintoandar.atlassian.net/jira/software/projects/DTM/boards/417?selectedIssue=DTM-635)