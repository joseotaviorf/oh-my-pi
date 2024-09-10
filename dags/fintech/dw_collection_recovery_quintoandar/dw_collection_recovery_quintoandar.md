## DW Collection Recovery QuintoAndar

### Purpose

This DAG creates the Collection Recovery model for QuintoAndar based on Recupera, Trato-Feito and Seu Barriga/Retsuko databases.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This dag is triggered once per day via Mediator. More information about run time [here]({chart_url}{dag_id})

### Outputs

This pipeline produces the following output tables:

- `dw_collection_recovery_quintoandar.dim_debtor`
- `dw_collection_recovery_quintoandar.dim_eviction`
- `dw_collection_recovery_quintoandar.fact_collection`
- `dw_collection_recovery_quintoandar.fact_debt`
- `dw_collection_recovery_quintoandar.fact_negotiation_installment`
- `dw_collection_recovery_quintoandar.fact_negotiation`
- `dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline`
- `dw_collection_recovery_quintoandar.bridge_map_debt_negotiation`
</details>
