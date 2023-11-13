## DW Retsuko

### Purpose

This DAG creates the Collection Recovery model based on Recupera, Trato-Feito and Seu Barriga/Retsuko databases.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This dag is triggered once per day via Mediator. More information about run time [here]({chart_url}{dag_id})

### Outputs

This pipeline produces the following output tables:

- `dw_collection_recovery.dim_debtor`
- `dw_collection_recovery.dim_eviction`
- `dw_collection_recovery.fact_collection`
- `dw_collection_recovery.fact_debt`
- `dw_collection_recovery.fact_negotiation_installment`
- `dw_collection_recovery.fact_negotiation`
- `dw_collection_recovery.fact_overdue_portfolio_timeline`
</details>
