## DW Affiliate Costs

### Purpose

This DAG creates the dim and fact that the Marketing Analysts will use to analyze the commission costs that occur in our Indica AI Program.  

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Dag Dependencies
`enrich_robin_hood` (all tasks)

### Dependent Dags
None

### Execution Interval
This dag is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id})

### Outputs

This pipeline produces the following output tables: 

- `fact_affiliate_costs` – Granularity is one accounting entry from our Robin Hood tables
- `dim_affiliate_costs` – Contains information about each Affiliate Cost.  

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>
