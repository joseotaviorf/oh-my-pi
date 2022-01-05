## Enrich Invoice

### Purpose
This DAG creates the full table for credit invoice enrichment, with information about payments.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output table: 

1. In data lake enrich:
- `credit_invoice`
- `invoice_all`
- `invoice_entries`
- `invoice_revenues`

### Responsible Data Teams
For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>
