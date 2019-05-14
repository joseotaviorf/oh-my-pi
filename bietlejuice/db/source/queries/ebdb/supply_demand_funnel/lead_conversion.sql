select
  id,
  dataConversao as ts_converted,
  imovel_id as id_house,
  leadConvertido_id as id_lead,
  vendedor_id as id_seller,
  gerenteContas_id as id_account_manager,
  atualizadoEm as ts_updated,
  criadoEm as ts_created,
  validado as is_valid,
  status,
  tipo as type
from ConversaoLead
where date(coalesce(criadoEm, '1900-01-01 00:00:00')) <= date('{max_extraction_date}')
;