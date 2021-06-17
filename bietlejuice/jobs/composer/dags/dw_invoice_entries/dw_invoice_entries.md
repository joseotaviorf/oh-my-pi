## DW Invoice Entries
​
### Purpose
​
This DAG creates the fact model for invoice entries.  
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered daily, via Mediator. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output model, in DW schema `payment`, via full load:​​

- `fact_invoice_entries`
​
### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>