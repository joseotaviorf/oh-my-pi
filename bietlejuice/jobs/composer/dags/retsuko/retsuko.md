## Retsuko
### Purpose

Retrieve data from Retsuko database (postgresql). [Retsuko](https://github.com/quintoandar/retsuko) is responsible to Extract financial data, Transform and Load it (ETL) in Metabase to be able to generate financial reports. It does not create or owns any information and it is not its purpose to do that. All the data it has comes from other financial services (today is only [SeuBarriga](https://github.com/quintoandar/seubarriga)).

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following tables into the datalake:

1. In datalake raw:

    * account
    * boleto
    * change_owner_control
    * contract
    * credit_card_payment
    * entry
    * file
    * invoice
    * monthly_closing_checks
    * pg_stat_statements
    * vw_billable

2. In datalake clean

    * account
    * boleto
    * contract
    * credit_card_payment
    * entry
    * file
    * invoice

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
