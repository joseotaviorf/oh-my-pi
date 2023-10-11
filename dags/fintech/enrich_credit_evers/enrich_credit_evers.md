## Enrich Credit Evers

### Purpose
Creates the enriched tables for Credit Evers context, which runs every month at day 15.

The Ever concept determines whether a tenant on 5A is a delinquent or not. A given contract is considered an EverXMobY if it has at least one invoice overdue by X days in the first Y months of the contract.

This concept is closely related to the concept of an Over invoice. This table will bring benefits to Credit Analytics Team and Data Products Team, in order to produce Machine Learning models.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs
Produces the following output table in enrich layer, via full load:

    - `credit_evers`
    - `credit_evers_original_due_date`
    - `credit_evers_full_original_due_date`

</details>
