## DW Invoice Entries
​
### Purpose
​
This DAG creates the fact model for invoice entries.  
​
### Execution​ Interval

This DAG is triggered daily, via Mediator. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output model: 

In DW, schema `payment`:​​
- `fact_invoice_entries`
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
