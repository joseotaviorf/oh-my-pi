## Vans
​
### Purpose
​
This DAG creates the full tables for Vans, the integration with VAN service, responsible for the exchange with financial agents.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval
This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables:

1. In data lake raw:

    - All tables available in source's database, except for operational table `schema_migrations`.

2. In data lake clean:​​

    - `bank`
    - `bank_boleto`
    - `bank_boleto_requested_by`
    - `bank_payment`
    - `bank_payment_requested_by`
    - `boleto`
    - `boleto_file`
    - `boleto_our_number_counter`
    - `file`
    - `file_payment`
    - `file_payment_boleto`
    - `payment`
    - `payment_boleto`

​
</details>
