## DW Revenue Lines

### Purpose

This DAG creates the Revenue Lines model, which provides information about financial income of our rental contracts.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This dag is triggered once per day via Mediator. More information about run time [here]({chart_url}{dag_id})

### Outputs

This pipeline produces the following output tables: 

- `dw_revenue_lines.dim_brokerage_finance`
- `dw_revenue_lines.dim_credit_card_payment`
- `dw_revenue_lines.dim_late_payments`
- `dw_revenue_lines.dim_long_term_rental_anticipation`
- `dw_revenue_lines.dim_month_rental_anticipation`
- `dw_revenue_lines.dim_rental_guarantee`
- `dw_revenue_lines.dim_reservation`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>
