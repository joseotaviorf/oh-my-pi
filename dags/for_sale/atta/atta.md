## Atta

### Purpose

This DAG imports data from Atta which is one of 5A's acquisitions. Its main product is called iSolve which main focus is to manage the fluxes regarding internal financing options in ForSale contracts.


<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

In datalake RAW, via full load:

- `banktracking`
- `cliente`
- `closing`
- `closing_file`
- `commission_revenue_share_params`
- `commission_revenue_share_periods`
- `consulta_score`
- `consulta_score_bradesco`
- `consulta_score_bradesco_params`
- `consulta_score_bradesco_ratings`
- `consulta_score_caixa`
- `consulta_score_cliente_ctrl`
- `consulta_score_ctrl`
- `consulta_score_itau`
- `consulta_score_itau_ratings`
- `consulta_score_santander`
- `consulta_score_santander_matriz_decisao`
- `consulta_score_santander_ratings`
- `entidade_log`
- `fornecedores`
- `franquia`
- `log_proposta_esteira`
- `max_usuarios`
- `parceiro`
- `parceiro_categoria`
- `produto`
- `produto_esteira`
- `proposta`
- `proposta_credimob_confval`
- `proposta_itau`
- `proposta_observacao`
- `reconciliation_item`
- `storagedocumentos`

In datalake RAW, via incremental load:

- `systemlogs`



In datalake CLEAN, via full load:

- `bank_tracking`
- `client_info`
- `closing`
- `closing_file`
- `commission_revenue_share_params`
- `commission_revenue_share_periods`
- `financing_proposal`
- `financing_proposal_check`
- `franchise_info`
- `log_isolve_v1`
- `log_isolve_v2`
- `partner_category`
- `partner_info`
- `pre_analysis`
- `pre_analysis_bradesco`
- `pre_analysis_bradesco_params`
- `pre_analysis_bradesco_ratings`
- `pre_analysis_caixa`
- `pre_analysis_client_ctrl`
- `pre_analysis_ctrl`
- `pre_analysis_itau`
- `pre_analysis_itau_ratings`
- `pre_analysis_santander`
- `pre_analysis_santander_matrix`
- `pre_analysis_santander_ratings`
- `product_info`
- `proposal`
- `proposal_notes`
- `providers_info`
- `reconciliation_item`
- `storage_documents`
- `track_step_detail`
- `users_info`

In datalake CLEAN, via incremental load:

- `system_logs`
