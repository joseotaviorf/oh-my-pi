drop view if exists unit_economics.vw_base_contract_costs;
create or replace view unit_economics.vw_base_contract_costs as
select
  id,
  imovel_id as property_id,
  status,
  "valorAluguel" as rent_value,
  ("valorCondominio" + "valorAluguel") as package_value,
  "dataRescisao" as termination_date,
  "dataFimContratoPrevisto" as expected_end_date,
  "dataAssinado" as signature_date,
  "dataEntrada" as entrance_date,
  "dataInicio" as init_date,
  "criadoEm" as created_date
from contract
where tipo = 'FullService'
    and status in ('Finalizado', 'Ativo')
    and date_trunc('month', "dataAssinado") >= '2016-01-01'
    and date_trunc('month', "dataEntrada") >= '2016-01-01'
    and date_trunc('month', "dataInicio") >= '2016-01-01'
;