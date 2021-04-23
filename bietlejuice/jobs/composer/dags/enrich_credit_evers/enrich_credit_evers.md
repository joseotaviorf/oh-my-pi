## Enrich Credit Evers

### Purpose

Creates the enriched tables for Credit Evers context. 

The Ever concept determines whether a tenant on 5A is a delinquent or not. A given contract is considered an EverXMobY if it has at least one invoice overdue by X days in the first Y months of the contract.

This concept is closely related to the concept of an Over invoice. This table will bring benefits to Credit Analytics Team and Data Products Team, in order to produce Machine Learning models.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table in enrich layer:
    - `credit_evers`
    - `credit_evers_original_due_date`

### Responsible Data Teams

For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
