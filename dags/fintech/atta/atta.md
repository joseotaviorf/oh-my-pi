## Atta

### Purpose

This DAG imports data from Atta which is one of 5A's acquisitions. Its main product is called iSolve which main focus is to manage the fluxes regarding internal financing options in ForSale contracts.


<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

In datalake RAW, via full load:

- `consulta_score`
- `entidade_log`
- `franquia`
- `fornecedores`
- `log_proposta_esteira`
- `parceiro`
- `produto`
- `produto_esteira`
- `proposta_itau`

via incremental load:


- `max_usuarios`
- `proposta`
- `proposta_credimob_confval`



In datalake CLEAN, via full load:

- `financing_proposal`
- `franchise_info`
- `log_isolve_v1`
- `log_isolve_v2`
- `partner_info`
- `pre_analysis`
- `product_info`
- `providers_info`
- `track_step_detail`


via incremental load:

- `financing_proposal_check`
- `proposal`
- `users_info`
