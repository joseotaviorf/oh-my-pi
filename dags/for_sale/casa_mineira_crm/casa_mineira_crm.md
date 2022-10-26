## Casa Mineira CRM

Retrieves data from Casa Mineira CRM and load it on datalake.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

1. In datalake raw:
    
  * atributo
  * atributo_tipo
  * bairro
  * chave
  * cidade
  * cliente
  * cliente_arquivado
  * cliente_atendimento
  * cliente_historico
  * cliente_lembrete
  * cliente_observacao
  * cliente_permissao
  * condominio
  * construtora
  * contato
  * contato_midia
  * contato_origem
  * documento
  * documento_tipo
  * ficha
  * imagem
  * imovel
  * imovel_atributo
  * imovel_captacao_participante
  * imovel_exclusividade
  * placa
  * proprietario
  * registro_acesso
  * registro_exibicao
  * revisions
  * solicitacao_alteracao
  * solicitacao_alteracao_tipo
  * status
  * tipo
  * uf
  * unidade
  * usuario
  * usuario_avaliacao_imovel
  * usuario_comissao_imovel
  * usuario_grupo
  * usuario_login
  * venda
  * venda_comissao
  * visita
  * visita_solicitacao

2. In datalake clean
    
  * archived_client
  * attribute_type
  * attribute
  * builder
  * change_request
  * change_request_type
  * city
  * client
  * client_attendance
  * client_history
  * client_observation
  * client_pemission
  * client_reminder
  * condo
  * contact
  * document
  * document_type
  * form
  * house
  * house_attribute
  * house_exclusivity
  * house_status
  * house_type
  * keys
  * media_contact
  * neighborhood
  * origin_contact
  * owner
  * register_access
  * register_exhibition
  * revision
  * sale
  * sale_brokerage
  * sign
  * uf
  * unity
  * user_group
  * user_house_brokerage
  * user_house_evaluation
  * user_login
  * user
  * visit
  * visit_request
    
### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>