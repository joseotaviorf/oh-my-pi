## DW Charging Payment QuintoCred


### Purpose

​
This DAG creates the star schema model for QuintoCred Charging Payment context.
​

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered daily, via Mediator.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

​
This pipeline produces the following output model, in DW schema `charging_payment_quintocred`, via full load:​​

- `fact_propose_timeline`
- `fact_direct_billing`
- `fact_charging_payment`
- `fact_delinquecy`
- `fact_payment_delinquency`
- `fact_theoretical_payment_delinquency`
- `fact_accounting_funnel`
- `fact_payment_full`
​
</details>
