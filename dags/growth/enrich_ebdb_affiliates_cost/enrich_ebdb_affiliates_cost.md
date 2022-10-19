## Enrich EBDB Affiliates Cost

### Purpose

EBDB Affiliates Cost DAG retrieves QuintoAndar's EBDB affiliate commission values classified according to each account transaction type:

- `valorFixoPorIndicacaoDeImovel`
- `porcentagemPorIndicacaoDeImovel`
- `comissaoUnicaSobreAfiliadoIndicado`

These values are accounted in Growth flows as commission costs and are debited from conversion incomes.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table via incremental load:

**enrich**:

- datalake_affiliates_cost.affiliates_engagement_cost
