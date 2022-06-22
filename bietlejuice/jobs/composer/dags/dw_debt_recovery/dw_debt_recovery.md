## DW Debt Recovery

### Purpose

​
This DAG loads the DW tables with business rules for Analysis of mostly Trato Feito - a product to handle customer debts - based metrics. The purpose of this model is to easy the understanding of Debt Recovery that Trato Feito and Recupera (third-party service) handles.

​<details>

  <summary><strong> > DAG details (click to expand)</strong></summary>​
​
### Execution​ Interval
This DAG is triggered once per day via Mediator, after `enrich_debt_recovery`.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

​
This pipeline produces the following output tables incrementally:
​

- `fact_installment`
- `fact_negotiation`

​

</details>
