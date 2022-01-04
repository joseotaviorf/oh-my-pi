## Enrich Retsuko
### Purpose

Prepares **finantial** data from the [Retsuko](github.com/quintoandar/retsuko) for business utilization. Retrieve data from Retsuko database (postgresql). [Retsuko](https://github.com/quintoandar/retsuko) is responsible to Extract financial data, Transform and Load it (ETL) in Metabase to be able to generate financial reports. It does not create or owns any information and it is not its purpose to do that. All the data it has comes from other financial services (today is only [SeuBarriga](https://github.com/quintoandar/seubarriga)).
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once per day via Mediator, after `retsuko` DAG, usually around 11:45 A.M. UTC.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer:

- `invoice`
- `invoice_entry`

### Responsible Data Teams
​
For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​</details>