## Enrich Revenue Lines

### Purpose

This DAG creates the enriched tables for Revenue Lines model.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered daily, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following tables in enrich layer, via full load:

- `brokerage_finance`
- `credit_card_payment`
- `late_payments`
- `long_term_rental_anticipation`
- `month_rental_anticipation`
- `rental_guarantee`
- `reservation`

​</details>
