## Condominium Payments

### Purpose

Retrieve data from Condominium Payments database (postgresql) [Condominium Payments](https://github.com/quintoandar/infrastructure/blob/master/vault/database/postgres/prod/condominium-payments-api/main.tf) into data lake. This data comes from Condominium Payments API [Condominium Payments API](https://github.com/quintoandar/condominium-payments-api).

Condominium Payments is an API that checks non-payment reports and keeps business rules related to the workflow of condominium-related payments.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following tables into the datalake:

1. In datalake raw:
   - `attachment`
   - `internalization`
   - `non_payment_report`
   - `non_payment_report_invoice`
2. In datalake clean:
   - `attachment`
   - `internalization`
   - `non_payment_report`
   - `non_payment_report_invoice`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact its owner.

</details>
