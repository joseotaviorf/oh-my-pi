## DW User Sales Rep

### Purpose
​
This DAG creates the modeling for User Sales Rep, users who are internal or outsourced salespeople.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered once per day via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following modeling in DW, via full load:
    - `dim_user_sales_rep`

​
### Additional Information
​
!!After finishing ODS Migration, this modeling should be moved to the `dw_user` DAG!!
</details>