drop view if exists vw_dim_lead_conversion;
create view vw_dim_lead_conversion
as
SELECT
  id as sk_lead_conversion,
  id as id_lead_conversion,
  imovel_id as id_imovel,
  "leadConvertido_id" id_converted_lead,
  vendedor_id as id_salesperson,
  "gerenteContas_id" as id_account_manager,
  validado as validated,
  status,
  tipo as type,
  "dataConversao" as dt_conversion,
  "atualizadoEm" as dt_updated,
  "criadoEm" as dt_created,
  now()::timestamp as dt_timestamp
FROM
  public.lead_conversion ;