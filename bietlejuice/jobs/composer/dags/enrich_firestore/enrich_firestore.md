## Enrich Firestore

### Purpose
This DAG creates the enriched tables from Firestore data, for ForSale. 
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator, after `firestore` DAG. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following tables in enrich layer, via full load:
- `monday`
- `rent_offer`
- `sale_offer`

### Responsible Data Teams
​
For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​</details>