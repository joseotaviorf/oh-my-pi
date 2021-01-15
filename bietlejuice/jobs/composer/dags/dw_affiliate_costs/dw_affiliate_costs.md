## DW Affiliate Costs
​
### Purpose
​
This DAG creates the dim and fact that the Marketing Analysts will use to analyze the commission costs that occur in our Indica AI Program.  
​
### Dag Dependencies
`enrich_robin_hood` (all tasks)

### Dependent Dags
None

### Execution​ Interval
This dag is trigged once per day via Mediator.

More information about run time [here]({chart_url}{dag_id})
### Outputs
​
This pipeline produces the following output tables: 
​
- `fact_affiliate_costs` – Granularity is one accounting entry from our Robin Hood tables
- `dim_affiliate_costs` – Contains information about each Affiliate Cost.  
​
### Responsible Data Engineering Team
​
For any questions or concerns, please contact the Data Marketing Team.  
​
### Additional Information
​
If you need additional information about how the Indica AI Program works you can talk to an analyst on the Data Marketing Team.  
​
### Major Changes (JIRA Tasks)
​
[DTM-589](https://quintoandar.atlassian.net/jira/software/projects/DTM/boards/417?selectedIssue=DTM-589)