## Enrich Retsuko

### Purpose

Prepares **finantial** data from the [Retsuko](github.com/quintoandar/retsuko) for business utilization. Retrieve data from Retsuko database (postgresql). [Retsuko](https://github.com/quintoandar/retsuko) is responsible to Extract financial data, Transform and Load it (ETL) in Metabase to be able to generate financial reports. It does not create or owns any information and it is not its purpose to do that. All the data it has comes from other financial services (today is only [SeuBarriga](https://github.com/quintoandar/seubarriga)).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once per day via Mediator, after `retsuko` DAG, usually around 11:45 A.M. UTC.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables deduplicated on enrich layer:

- `bill`
- `entry`
- `invoice`


This pipeline produces the following output tables enriched on enrich layer:
- `bill_items`
- `invoice_entry`
- `invoice_info`
- `monthly_closing_checks`

​</details>
