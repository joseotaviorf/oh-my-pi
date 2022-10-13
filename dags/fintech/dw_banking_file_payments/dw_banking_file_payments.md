## DW Banking File Payments

​

### Purpose

​
This DAG creates models for banking file payments from Vans source.
​

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered daily, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

​
This pipeline produces the following output model, in DW schema `payment`, via full load:​​

- `dim_banking_file_payment`
- `dim_occurrence_code`
- `fact_banking_file_payments`

</details>
