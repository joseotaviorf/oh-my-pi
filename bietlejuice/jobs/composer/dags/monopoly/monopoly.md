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

    * account
    * accounting_entry
    * income
    * income_reference
    * income_status_log
    * outcome
    * outcome_reference
    * outcome_status_log
    * person
    * person_sale
    * sale
    * sale_revision
    * sale_transactions

2. In datalake clean
    
    * account
    * accounting_entry
    * income
    * income_reference
    * income_status_log
    * outcome
    * outcome_reference
    * outcome_status_log
    * person
    * person_sale
    * sale
    * sale_revision
    * sale_transactions
    
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>