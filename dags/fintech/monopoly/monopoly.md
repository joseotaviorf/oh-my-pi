## Monopoly

### Purpose

Retrieve data from Monopoly database (postgresql). [Monopoly](https://github.com/quintoandar/monopoly) is a microservice responsible for payment and charge business rules of selling houses.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following tables into the datalake, via full load:

1. In datalake raw:

   - account
   - accounting_entry
   - income
   - income_reference
   - income_status_log
   - nota_fiscal_emission_error
   - outcome
   - outcome_reference
   - outcome_status_log
   - person
   - person_sale
   - revenue_share
   - sale
   - sale_revision
   - sale_transactions

2. In datalake clean

   - account
   - accounting_entry
   - income
   - income_reference
   - income_status_log
   - nota_fiscal_emission_error
   - outcome
   - outcome_reference
   - outcome_status_log
   - person
   - person_sale
   - revenue_share
   - sale
   - sale_revision
   - sale_transactions

</details>
